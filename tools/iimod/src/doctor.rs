//! Doctor command: environment report and optional registry rebuild.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::hostpatch;
use crate::ops::{patch_records_for, validate_payload, wipe_banner};
use crate::paths;
use crate::qs;
use crate::registry::{self, InstalledModule, ModuleState, Registry};
use crate::store;

pub fn cmd_doctor(rebuild_registry: bool) -> Result<()> {
    print_environment_report();
    if rebuild_registry {
        return rebuild_registry_from_store();
    }
    print_registry_report();
    Ok(())
}

fn print_environment_report() {
    let ii = paths::ii_root();
    println!("iimod {}", hostpatch::HOST_VERSION);
    println!(
        "ii root: {} ({})",
        ii.display(),
        if ii.join("shell.qml").exists() {
            "present"
        } else {
            "MISSING"
        }
    );
    println!("state root: {}", paths::state_root().display());
    println!(
        "qs: {}",
        qs::qs_version().unwrap_or_else(|| "not found".into())
    );
    println!("shell running: {}", qs::shell_running());
    println!(
        "host ipc: {}",
        if qs::ping() {
            "reachable"
        } else {
            "unreachable"
        }
    );
}

fn rebuild_registry_from_store() -> Result<()> {
    let rebuilt = recover_registry_from_store()?;
    registry::save(&rebuilt)?;
    println!(
        "✓ registry rebuilt ({} modules, all disabled — enable + reapply as needed)",
        rebuilt.modules.len()
    );
    Ok(())
}

fn recover_registry_from_store() -> Result<Registry> {
    let mut rebuilt = Registry::default();
    if let Ok(entries) = std::fs::read_dir(paths::store_dir()) {
        for entry in entries.flatten() {
            if let Some(module) = recover_store_entry(&entry)? {
                rebuilt.modules.push(module);
            }
        }
    }
    Ok(rebuilt)
}

fn recover_store_entry(entry: &std::fs::DirEntry) -> Result<Option<InstalledModule>> {
    let id = entry.file_name().to_string_lossy().into_owned();
    let Some(payload) = best_version_payload(&entry.path()) else {
        return Ok(None);
    };
    let Ok(module) = installed_module_from_payload(&payload) else {
        return Ok(None);
    };
    println!("recovered from store: {id}");
    Ok(Some(module))
}

fn best_version_payload(module_store_dir: &Path) -> Option<PathBuf> {
    let mut best: Option<(semver::Version, PathBuf)> = None;
    let versions = std::fs::read_dir(module_store_dir).ok()?;
    for version in versions.flatten() {
        let Ok(parsed) = semver::Version::parse(&version.file_name().to_string_lossy()) else {
            continue;
        };
        if best.as_ref().is_none_or(|(current, _)| parsed > *current) {
            best = Some((parsed, version.path()));
        }
    }
    best.map(|(_, payload)| payload)
}

fn installed_module_from_payload(payload: &Path) -> Result<InstalledModule> {
    let (manifest, _) = validate_payload(payload)?;
    let patch_records = patch_records_for(&manifest);
    Ok(InstalledModule {
        files: store::hash_tree(payload)?,
        manifest,
        state: ModuleState::Disabled,
        patch_records,
        translation_keys: BTreeMap::new(),
        installed_at_epoch: registry::now_epoch(),
    })
}

fn print_registry_report() {
    match registry::load() {
        Ok(registry) => {
            println!("registry: ok ({} modules)", registry.modules.len());
            wipe_banner(&registry);
            print_host_report();
        }
        Err(e) => println!("registry: CORRUPT ({e}) — run: iimod doctor --rebuild-registry"),
    }
}

fn print_host_report() {
    let sentinel = hostpatch::read_sentinel();
    match sentinel {
        Some(s) => println!(
            "host: v{} (installed {})",
            s.host_version, s.installed_at_epoch
        ),
        None => println!("host: not installed"),
    }
}
