//! Shared command operations: payload loading, validation, projection, and
//! stock-file recomposition.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::lint;
use crate::manifest::{self, Manifest, Slot};
use crate::patch::{self, PatchInstance};
use crate::paths;
use crate::pkg;
use crate::qs;
use crate::registry::{self, ModuleState, Registry};
use crate::translations;

pub(crate) struct Payload {
    pub(crate) dir: PathBuf,
    pub(crate) from_package: bool,
    /// Update origin embedded in the package's integrity.json, if any.
    pub(crate) embedded_origin: Option<String>,
    /// Temp extraction dir to clean up on drop (packages only).
    _tmp: Option<PathBuf>,
}

pub(crate) fn load_payload(source: &Path, max_size: u64) -> Result<Payload> {
    if source.is_dir() {
        return Ok(Payload {
            dir: source.to_path_buf(),
            from_package: false,
            embedded_origin: None,
            _tmp: None,
        });
    }
    if source.is_file() {
        let tmp = paths::tmp_dir().join(format!(
            "unpack-{}-{}",
            registry::now_epoch(),
            std::process::id()
        ));
        let unpacked = pkg::unpack(source, &tmp, max_size)?;
        return Ok(Payload {
            dir: unpacked.payload,
            from_package: true,
            embedded_origin: unpacked.integrity.origin.clone(),
            _tmp: Some(tmp),
        });
    }
    Err(bail(
        exit::USAGE,
        format!("no such file or directory: {}", source.display()),
    ))
}

/// Parse + validate manifest, payload layout, lint, translations. Returns
/// (manifest, warnings).
pub(crate) fn validate_payload(payload: &Path) -> Result<(Manifest, Vec<String>)> {
    let manifest_path = payload.join("module.json");
    let bytes = std::fs::read(&manifest_path).map_err(|_| {
        bail(
            exit::VALIDATION,
            format!("{}: module.json missing", payload.display()),
        )
    })?;
    let m = manifest::parse(&bytes)?;
    let mut warnings = manifest::validate(&m)?;

    let dir_name = payload
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default();
    if dir_name != m.id {
        return Err(bail(
            exit::VALIDATION,
            format!("payload dir {dir_name:?} != manifest id {:?}", m.id),
        ));
    }
    for slot in &m.slots {
        let entry = m.entry_for(*slot);
        if !payload.join(entry).is_file() {
            return Err(bail(
                exit::VALIDATION,
                format!("declared slot entry missing: {entry}"),
            ));
        }
    }
    if let Some(settings) = &m.entries.settings {
        if !payload.join(settings).is_file() {
            return Err(bail(
                exit::VALIDATION,
                format!("entries.settings missing: {settings}"),
            ));
        }
    }

    let report = lint::lint(&m, payload, &paths::ii_root())?;
    warnings.extend(report.warnings.clone());
    lint::require_clean(&report)?;

    translations::load_module_dicts(payload)?; // parse/locale validation
    Ok((m, warnings))
}

/// Dependencies, conflicts, system binaries against the registry + system.
pub(crate) fn check_deps_conflicts(m: &Manifest, registry: &Registry) -> Result<()> {
    let mut problems = Vec::new();
    for dep in &m.requires.modules {
        match registry.get(&dep.id) {
            None => problems.push(format!(
                "missing required module {:?} ({})",
                dep.id, dep.version_req
            )),
            Some(installed) => {
                let version = installed.manifest.semver()?;
                let req = semver::VersionReq::parse(&dep.version_req).expect("validated");
                if !req.matches(&version) {
                    problems.push(format!(
                        "module {:?} v{} does not satisfy {:?}",
                        dep.id, version, dep.version_req
                    ));
                }
            }
        }
    }
    for sys in &m.requires.system {
        let found = std::env::var_os("PATH")
            .is_some_and(|path| std::env::split_paths(&path).any(|d| d.join(&sys.bin).is_file()));
        if !found {
            problems.push(format!(
                "missing system binary {:?} (hint: {})",
                sys.bin, sys.hint
            ));
        }
    }
    for c in &m.conflicts {
        if registry.get(c).is_some() {
            problems.push(format!("conflicts with installed module {c:?}"));
        }
    }
    for installed in &registry.modules {
        if installed.manifest.conflicts.contains(&m.id) {
            problems.push(format!(
                "installed module {:?} declares a conflict with this module",
                installed.manifest.id
            ));
        }
    }
    if problems.is_empty() {
        Ok(())
    } else {
        Err(bail(
            exit::DEPENDENCY,
            format!("dependency check failed:\n  ✗ {}", problems.join("\n  ✗ ")),
        ))
    }
}

/// All patches for `rel` from host + registry (minus `exclude` module).
pub(crate) fn full_patch_set(
    registry: &Registry,
    rel: &str,
    exclude: Option<&str>,
) -> Vec<PatchInstance> {
    let mut set: Vec<PatchInstance> = hostpatch::host_patches()
        .into_iter()
        .filter(|(f, _)| *f == rel)
        .map(|(_, p)| p)
        .collect();
    set.extend(
        registry
            .patches_for_file(rel)
            .into_iter()
            .filter(|p| Some(p.owner.as_str()) != exclude),
    );
    set.sort_by_key(|p| (p.owner.clone(), p.index));
    set
}

pub(crate) fn patch_records_for(manifest: &Manifest) -> BTreeMap<String, Vec<PatchInstance>> {
    let mut records: BTreeMap<String, Vec<PatchInstance>> = BTreeMap::new();
    for (i, p) in manifest.patches.iter().enumerate() {
        records
            .entry(p.file.clone())
            .or_default()
            .push(PatchInstance {
                owner: manifest.id.clone(),
                index: i as u32,
                version: manifest.version.clone(),
                op: p.op,
                anchor: p.anchor.clone(),
                content: p.content.clone(),
            });
    }
    records
}

pub(crate) const HOST_FILES: [&str; 4] = [
    "modules/common/Config.qml",
    "modules/ii/bar/BarContent.qml",
    "settings.qml",
    "shell.qml",
];

/// Every stock file needing recomposition: the four host files + all patch targets.
pub(crate) fn all_stock_targets(registry: &Registry, extra: &[String]) -> Vec<String> {
    let mut files: Vec<String> = HOST_FILES.iter().map(|s| s.to_string()).collect();
    files.extend(registry.all_patched_files());
    files.extend(extra.iter().cloned());
    files.sort();
    files.dedup();
    // Safe live-reload order: shell.qml last.
    files.retain(|f| f != "shell.qml");
    files.push("shell.qml".into());
    files
}

/// Recompose every affected stock file (host files + all patch targets) from
/// the registry's surviving patch sets. Dry-runs all files before writing any.
pub(crate) fn recompose_all(registry: &Registry, write: bool) -> Result<Vec<String>> {
    let ii = paths::ii_root();
    let targets = all_stock_targets(registry, &[]);
    let mut planned: Vec<(PathBuf, String)> = Vec::new();
    let mut touched = Vec::new();

    for rel in &targets {
        let target = ii.join(rel);
        if !target.exists() {
            if HOST_FILES.contains(&rel.as_str()) {
                return Err(bail(exit::STATE, format!("stock file missing: {rel}")));
            }
            continue;
        }
        let current = std::fs::read_to_string(&target)?;
        let set = full_patch_set(registry, rel, None);
        let composed = patch::recompose(&current, &set)?;
        if composed != current {
            planned.push((target, composed));
            touched.push(rel.clone());
        }
    }
    if write {
        for (target, composed) in planned {
            std::fs::write(target, composed)?;
        }
    }
    Ok(touched)
}

/// Rebuild ~/.config/illogical-impulse/modules/index.json from the registry.
pub(crate) fn write_index_projection(registry: &Registry) -> Result<()> {
    let modules: Vec<serde_json::Value> = registry
        .modules
        .iter()
        .map(|m| {
            serde_json::json!({
                "id": m.manifest.id,
                "name": m.manifest.name,
                "description": m.manifest.description,
                "version": m.manifest.version,
                "slots": m.manifest.slots,
                "state": m.state,
                "settings": m.manifest.entries.settings,
                "tierB": m.manifest.is_tier_b(),
            })
        })
        .collect();
    let index = serde_json::json!({ "generatedBy": format!("iimod {}", hostpatch::HOST_VERSION), "modules": modules });
    std::fs::create_dir_all(paths::modules_config_dir())?;
    let path = paths::index_projection_path();
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_string_pretty(&index)? + "\n")?;
    std::fs::rename(&tmp, &path)?;
    Ok(())
}

/// Flip enabled state: host IPC preferred; direct config.json edit as fallback.
pub(crate) fn project_enabled(registry: &Registry) -> Result<()> {
    let mut bar: Vec<String> = Vec::new();
    let mut window: Vec<String> = Vec::new();
    for m in &registry.modules {
        if matches!(m.state, ModuleState::Enabled) {
            if m.manifest.slots.contains(&Slot::Bar) {
                bar.push(m.manifest.id.clone());
            }
            if m.manifest.slots.contains(&Slot::Window) {
                window.push(m.manifest.id.clone());
            }
        }
    }
    bar.sort();
    window.sort();

    if qs::ping() {
        // Reconcile via IPC: the shell applies each id itself (single writer).
        let mut ok = true;
        for m in &registry.modules {
            let enabled = matches!(m.state, ModuleState::Enabled);
            if m.manifest.slots.contains(&Slot::Bar) {
                ok &= qs::set_enabled(&m.manifest.id, "bar", enabled);
            }
            if m.manifest.slots.contains(&Slot::Window) {
                ok &= qs::set_enabled(&m.manifest.id, "window", enabled);
            }
        }
        // Ghost cleanup: ids still enabled in config.json but no longer in the
        // registry (uninstalled) must be switched off explicitly.
        let config_path = paths::shell_config_root().join("config.json");
        if let Some(cfg) = std::fs::read(&config_path)
            .ok()
            .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        {
            for (key, slot) in [("enabledBar", "bar"), ("enabledWindow", "window")] {
                for ghost in cfg["iimp"][key].as_array().into_iter().flatten() {
                    if let Some(id) = ghost.as_str() {
                        if registry.get(id).is_none() {
                            ok &= qs::set_enabled(id, slot, false);
                        }
                    }
                }
            }
        }
        if ok {
            return Ok(());
        }
    }

    // Fallback: direct config.json edit (shell down → no writer race).
    let config_path = paths::shell_config_root().join("config.json");
    let mut root: serde_json::Value = std::fs::read(&config_path)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_else(|| serde_json::json!({}));
    root["iimp"] = serde_json::json!({ "enabledBar": bar, "enabledWindow": window });
    if let Some(parent) = config_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = config_path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_string_pretty(&root)? + "\n")?;
    std::fs::rename(&tmp, &config_path)?;
    Ok(())
}

/// Ids to statically register via ModuleImports.qml: every installed module
/// whose payload dir is on disk (incompatible modules may lack one) AND
/// exposes at least one QML type. A dotted directory import only resolves if
/// the directory contains an uppercase-named .qml type; a payload holding just
/// entry files (main.qml, bar.qml) is an empty QML module and importing it
/// fails the whole shell reload with "module ... is not installed".
pub(crate) fn module_import_ids(registry: &Registry) -> Vec<String> {
    let mut ids: Vec<String> = registry
        .modules
        .iter()
        .filter(|m| dir_exposes_qml_types(&paths::mod_root().join(&m.manifest.id)))
        .map(|m| m.manifest.id.clone())
        .collect();
    ids.sort();
    ids
}

/// True if the directory contains at least one `Uppercase*.qml` — the QML
/// implicit-module rule for whether a directory import registers any types.
fn dir_exposes_qml_types(dir: &std::path::Path) -> bool {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return false;
    };
    entries.flatten().any(|e| {
        let name = e.file_name();
        let name = name.to_string_lossy();
        name.ends_with(".qml") && name.chars().next().is_some_and(|c| c.is_ascii_uppercase())
    })
}

pub(crate) fn wipe_banner(registry: &Registry) -> bool {
    if hostpatch::is_wiped(!registry.modules.is_empty()) {
        eprintln!("╔══════════════════════════════════════════════════════════╗");
        eprintln!("║  WIPED — a dots-hyprland update reset ~/.config/quickshell ║");
        eprintln!("║  Installed modules are missing from the shell tree.        ║");
        eprintln!("║  Run:  iimod reapply                                        ║");
        eprintln!("╚══════════════════════════════════════════════════════════╝");
        return true;
    }
    false
}

#[cfg(test)]
mod import_ids_tests {
    use super::dir_exposes_qml_types;

    #[test]
    fn entry_only_payload_exposes_no_types() {
        let dir = std::env::temp_dir().join("iimod_test_entry_only");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("main.qml"), "import QtQuick\nItem {}\n").unwrap();
        std::fs::write(dir.join("module.json"), "{}").unwrap();
        assert!(!dir_exposes_qml_types(&dir));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn uppercase_component_exposes_types() {
        let dir = std::env::temp_dir().join("iimod_test_has_type");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("bar.qml"), "import QtQuick\nItem {}\n").unwrap();
        std::fs::write(dir.join("TrafficLogic.qml"), "import QtQuick\nItem {}\n").unwrap();
        assert!(dir_exposes_qml_types(&dir));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn missing_dir_exposes_no_types() {
        assert!(!dir_exposes_qml_types(std::path::Path::new(
            "/nonexistent/iimod-test"
        )));
    }
}
