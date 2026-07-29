//! Verify installed module files, stock patch fences, and host presence.

use std::path::Path;

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::hoststate::{self, HostBundle};
use crate::ops::{full_patch_set, module_import_ids, wipe_banner};
use crate::patch;
use crate::paths;
use crate::registry::{self, InstalledModule, Registry};
use crate::store;

pub fn cmd_verify() -> Result<()> {
    let registry = registry::load()?;
    if report_wiped_tree(&registry) {
        return Err(bail(exit::STATE, "shell tree wiped — run: iimod reapply"));
    }

    let host = match hoststate::selected_for_read() {
        Ok(Some(host)) => Some(host),
        Ok(None) => None,
        Err(e) => {
            println!("{:<24} bundle-corrupt", "(host)");
            return Err(e);
        }
    };
    let ii = paths::ii_root();
    let mut bad = 0;
    for module in &registry.modules {
        let state = verify_module(host.as_ref(), &registry, module, &ii)?;
        if state != "intact" {
            bad += 1;
        }
        println!("{:<24} {}", module.manifest.id, state);
    }

    let host_state = host_state(&registry, host.as_ref());
    println!("{:<24} {}", "(host)", host_state);
    if bad > 0 || host_state != "intact" {
        return Err(bail(
            exit::STATE,
            "verify found problems — see states above (repair/reapply)",
        ));
    }
    println!("✓ all intact");
    Ok(())
}

fn report_wiped_tree(registry: &Registry) -> bool {
    if !wipe_banner(registry) {
        return false;
    }
    for module in &registry.modules {
        println!("{:<24} wiped", module.manifest.id);
    }
    true
}

fn verify_module(
    host: Option<&HostBundle>,
    registry: &Registry,
    module: &InstalledModule,
    ii: &Path,
) -> Result<&'static str> {
    let file_state = module_file_state(module);
    if file_state != "intact" {
        return Ok(file_state);
    }
    verify_patch_state(host, registry, module, ii)
}

fn module_file_state(module: &InstalledModule) -> &'static str {
    let dir = paths::mod_root().join(&module.manifest.id);
    if !dir.exists() {
        return "missing";
    }
    match store::hash_tree(&dir) {
        Ok(actual) if actual == module.files => "intact",
        Ok(_) => "module-modified",
        Err(_) => "missing",
    }
}

fn verify_patch_state(
    host: Option<&HostBundle>,
    registry: &Registry,
    module: &InstalledModule,
    ii: &Path,
) -> Result<&'static str> {
    let Some(host) = host else {
        return Ok("host-state-missing");
    };
    for rel in module.patch_records.keys() {
        let target = ii.join(rel);
        let current = std::fs::read_to_string(&target).unwrap_or_default();
        let Ok((stripped, _)) = patch::strip(&current) else {
            return Ok("fence-broken");
        };
        if stock_drifted(rel, &stripped) {
            return Ok("stock-drifted");
        }
        let expected = patch::compose(&stripped, &full_patch_set(host, registry, rel, None))?;
        if expected != current {
            return Ok("fence-broken");
        }
    }
    Ok("intact")
}

fn stock_drifted(rel: &str, stripped: &str) -> bool {
    store::read_pristine(rel).is_some_and(|pristine| stripped != pristine)
}

fn host_state(registry: &Registry, host: Option<&HostBundle>) -> &'static str {
    let Some(host) = host else {
        return if registry.modules.is_empty() && !paths::host_dir().exists() {
            "not-installed"
        } else {
            "descriptor-missing"
        };
    };
    let sentinel = match hostpatch::read_sentinel() {
        Some(value) => value,
        None => return "sentinel-missing",
    };
    if sentinel.host_generation != Some(host.descriptor.generation)
        || sentinel.content_id.as_deref() != Some(host.descriptor.content_id.as_str())
        || sentinel.protocol_version != host.descriptor.protocol_version
    {
        return "sentinel-mismatch";
    }
    if std::fs::read(paths::host_dir().join("ModuleHost.qml"))
        .ok()
        .as_deref()
        != Some(host.module_host_qml.as_slice())
        || std::fs::read(paths::host_dir().join("ModulesConfig.qml"))
            .ok()
            .as_deref()
            != Some(host.modules_config_qml.as_slice())
    {
        return "assets-modified";
    }
    let imports = hostpatch::module_imports_content(&module_import_ids(registry));
    if std::fs::read_to_string(paths::host_dir().join("ModuleImports.qml"))
        .ok()
        .as_deref()
        != Some(imports.as_str())
    {
        return "imports-modified";
    }
    if !hostpatches_match(host, registry) {
        return "host-fence-broken";
    }
    "intact"
}

fn hostpatches_match(host: &HostBundle, registry: &Registry) -> bool {
    let mut targets: Vec<&str> = host.patches.iter().map(|p| p.target.as_str()).collect();
    targets.sort_unstable();
    targets.dedup();
    targets.into_iter().all(|rel| {
        let path = paths::ii_root().join(rel);
        if !path.exists() && rel == hostpatch::VERTICAL_BAR_FILE {
            return true;
        }
        let current = match std::fs::read_to_string(path) {
            Ok(value) => value,
            Err(_) => return false,
        };
        let (stripped, _) = match patch::strip(&current) {
            Ok(value) => value,
            Err(_) => return false,
        };
        patch::compose(&stripped, &full_patch_set(host, registry, rel, None))
            .is_ok_and(|expected| expected == current)
    })
}
