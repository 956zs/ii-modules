//! Verify installed module files, stock patch fences, and host presence.

use std::path::Path;

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::ops::{full_patch_set, wipe_banner};
use crate::patch;
use crate::paths;
use crate::registry::{self, InstalledModule, Registry};
use crate::store;

pub fn cmd_verify() -> Result<()> {
    let registry = registry::load()?;
    if report_wiped_tree(&registry) {
        return Err(bail(exit::STATE, "shell tree wiped — run: iimod reapply"));
    }

    let ii = paths::ii_root();
    let mut bad = 0;
    for module in &registry.modules {
        let state = verify_module(&registry, module, &ii)?;
        if state != "intact" {
            bad += 1;
        }
        println!("{:<24} {}", module.manifest.id, state);
    }

    let host_state = host_state(&registry);
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

fn verify_module(registry: &Registry, module: &InstalledModule, ii: &Path) -> Result<&'static str> {
    let file_state = module_file_state(module);
    if file_state != "intact" {
        return Ok(file_state);
    }
    verify_patch_state(registry, module, ii)
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
    registry: &Registry,
    module: &InstalledModule,
    ii: &Path,
) -> Result<&'static str> {
    for rel in module.patch_records.keys() {
        let target = ii.join(rel);
        let current = std::fs::read_to_string(&target).unwrap_or_default();
        let Ok((stripped, _)) = patch::strip(&current) else {
            return Ok("fence-broken");
        };
        if stock_drifted(rel, &stripped) {
            return Ok("stock-drifted");
        }
        let expected = patch::compose(&stripped, &full_patch_set(registry, rel, None))?;
        if expected != current {
            return Ok("fence-broken");
        }
    }
    Ok("intact")
}

fn stock_drifted(rel: &str, stripped: &str) -> bool {
    store::read_pristine(rel).is_some_and(|pristine| stripped != pristine)
}

fn host_state(registry: &Registry) -> &'static str {
    if hostpatch::read_sentinel().is_none() && !registry.modules.is_empty() {
        return "wiped";
    }
    if hostpatch::host_files_present() || registry.modules.is_empty() {
        return "intact";
    }
    "missing"
}
