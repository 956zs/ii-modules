//! All iimod subcommands. Shared helpers first, then one section per command.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch::{self};
use crate::lint;
use crate::manifest::{self, Manifest, Slot};
use crate::patch::{self, PatchInstance};
use crate::paths;
use crate::pkg;
use crate::probe;
use crate::qs;
use crate::registry::{self, InstalledModule, Lock, ModuleState, Registry};
use crate::store::{self, BackupSet};
use crate::translations;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

struct Payload {
    dir: PathBuf,
    from_package: bool,
    /// Temp extraction dir to clean up on drop (packages only).
    _tmp: Option<PathBuf>,
}

fn load_payload(source: &Path, max_size: u64) -> Result<Payload> {
    if source.is_dir() {
        return Ok(Payload {
            dir: source.to_path_buf(),
            from_package: false,
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
fn validate_payload(payload: &Path) -> Result<(Manifest, Vec<String>)> {
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
fn check_deps_conflicts(m: &Manifest, registry: &Registry) -> Result<()> {
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
fn full_patch_set(registry: &Registry, rel: &str, exclude: Option<&str>) -> Vec<PatchInstance> {
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

const HOST_FILES: [&str; 4] = [
    "modules/common/Config.qml",
    "modules/ii/bar/BarContent.qml",
    "settings.qml",
    "shell.qml",
];

/// Every stock file needing recomposition: the four host files + all patch targets.
fn all_stock_targets(registry: &Registry, extra: &[String]) -> Vec<String> {
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
fn recompose_all(registry: &Registry, write: bool) -> Result<Vec<String>> {
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
fn write_index_projection(registry: &Registry) -> Result<()> {
    let modules: Vec<serde_json::Value> = registry
        .modules
        .iter()
        .map(|m| {
            serde_json::json!({
                "id": m.manifest.id,
                "name": m.manifest.name,
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
fn project_enabled(registry: &Registry) -> Result<()> {
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
/// whose payload dir is on disk (incompatible modules may lack one).
fn module_import_ids(registry: &Registry) -> Vec<String> {
    let mut ids: Vec<String> = registry
        .modules
        .iter()
        .filter(|m| paths::mod_root().join(&m.manifest.id).is_dir())
        .map(|m| m.manifest.id.clone())
        .collect();
    ids.sort();
    ids
}

fn wipe_banner(registry: &Registry) -> bool {
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

// ---------------------------------------------------------------------------
// validate / check
// ---------------------------------------------------------------------------

pub fn cmd_validate(source: &Path, max_size: u64) -> Result<()> {
    let payload = load_payload(source, max_size)?;
    let (m, warnings) = validate_payload(&payload.dir)?;
    if !payload.from_package {
        println!("note: directory source — package integrity not checked (pack + install the .iimod to cover it)");
    }
    for w in &warnings {
        println!("warning: {w}");
    }
    println!(
        "✓ {} v{} — manifest, layout, and lint OK ({})",
        m.id,
        m.version,
        if m.is_tier_b() {
            "Tier B: patches stock files"
        } else {
            "Tier A: slot-only"
        }
    );
    Ok(())
}

pub fn cmd_check(source: &Path, max_size: u64) -> Result<()> {
    let payload = load_payload(source, max_size)?;
    let (m, _) = validate_payload(&payload.dir)?;
    let registry = registry::load()?;
    check_deps_conflicts(&m, &registry)?;
    probe::require(&paths::ii_root(), &m.compat.probes)?;

    // Anchor dry-run for Tier B.
    let ii = paths::ii_root();
    for (i, p) in m.patches.iter().enumerate() {
        let target = ii.join(&p.file);
        let current = std::fs::read_to_string(&target).map_err(|_| {
            bail(
                exit::ANCHOR,
                format!("patches[{i}]: target {} unreadable", p.file),
            )
        })?;
        let mut set = full_patch_set(&registry, &p.file, Some(&m.id));
        set.push(PatchInstance {
            owner: m.id.clone(),
            index: i as u32,
            version: m.version.clone(),
            op: p.op,
            anchor: p.anchor.clone(),
            content: p.content.clone(),
        });
        patch::recompose(&current, &set)?;
    }
    println!(
        "✓ {} v{} is compatible with this shell (probes, deps, anchors all pass)",
        m.id, m.version
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// install
// ---------------------------------------------------------------------------

pub struct InstallOpts {
    pub allow_patches: bool,
    pub reinstall: bool,
    pub no_enable: bool,
    pub max_size: u64,
}

pub fn cmd_install(source: &Path, opts: &InstallOpts) -> Result<()> {
    let _lock = Lock::acquire()?;
    let registry = registry::load()?;
    if wipe_banner(&registry) {
        return Err(bail(
            exit::STATE,
            "shell tree is wiped; run `iimod reapply` before installing",
        ));
    }

    let payload = load_payload(source, opts.max_size)?;
    let (m, warnings) = validate_payload(&payload.dir)?;
    for w in &warnings {
        eprintln!("warning: {w}");
    }
    if !payload.from_package {
        eprintln!(
            "note: installing from a directory (developer mode) — no package integrity check"
        );
    }

    let upgrading = match registry.get(&m.id) {
        Some(existing) if existing.manifest.version == m.version && !opts.reinstall => {
            println!(
                "{} v{} already installed (use --reinstall to force)",
                m.id, m.version
            );
            return Ok(());
        }
        Some(existing) => Some(existing.manifest.version.clone()),
        None => None,
    };

    check_deps_conflicts(&m, &registry)?;
    probe::require(&paths::ii_root(), &m.compat.probes)?;

    if m.is_tier_b() && !opts.allow_patches {
        let files: Vec<&str> = m.patches.iter().map(|p| p.file.as_str()).collect();
        return Err(bail(
            exit::NEEDS_ALLOW_PATCHES,
            format!(
                "{} is a Tier B module: it modifies stock files {:?}.\nReview manifest patches[] and capabilities, then re-run with --allow-patches",
                m.id, files
            ),
        ));
    }

    // Build this module's patch records.
    let mut patch_records: BTreeMap<String, Vec<PatchInstance>> = BTreeMap::new();
    for (i, p) in m.patches.iter().enumerate() {
        patch_records
            .entry(p.file.clone())
            .or_default()
            .push(PatchInstance {
                owner: m.id.clone(),
                index: i as u32,
                version: m.version.clone(),
                op: p.op,
                anchor: p.anchor.clone(),
                content: p.content.clone(),
            });
    }

    // Dry-run: registry WITH the new module, compose in memory only.
    let mut next = registry.clone();
    next.remove(&m.id);
    next.modules.push(InstalledModule {
        manifest: m.clone(),
        state: ModuleState::Enabled,
        files: store::hash_tree(&payload.dir)?,
        patch_records: patch_records.clone(),
        translation_keys: BTreeMap::new(),
        installed_at_epoch: registry::now_epoch(),
    });
    let ii = paths::ii_root();
    for rel in all_stock_targets(&next, &[]) {
        let target = ii.join(&rel);
        if target.exists() {
            let current = std::fs::read_to_string(&target)?;
            patch::recompose(&current, &full_patch_set(&next, &rel, None))?;
        } else if HOST_FILES.contains(&rel.as_str()) {
            return Err(bail(exit::STATE, format!("stock file missing: {rel}")));
        } else {
            return Err(bail(exit::ANCHOR, format!("patch target missing: {rel}")));
        }
    }

    // ---- Mutation begins: journal + backups ------------------------------
    let backups = BackupSet::create()?;
    let stock_targets = all_stock_targets(&next, &[]);
    for rel in &stock_targets {
        backups.add(&format!("stock/{rel}"), &ii.join(rel))?;
    }
    backups.add(
        "config.json",
        &paths::shell_config_root().join("config.json"),
    )?;
    let module_dicts = translations::load_module_dicts(&payload.dir)?;
    for locale in module_dicts.keys() {
        backups.add(
            &format!("translations/{locale}.json"),
            &paths::translations_dir().join(format!("{locale}.json")),
        )?;
    }
    std::fs::write(
        paths::journal_path(),
        serde_json::to_string_pretty(&serde_json::json!({
            "op": "install", "id": m.id, "version": m.version,
            "backups": backups.dir, "stockTargets": stock_targets,
        }))? + "\n",
    )?;

    let module_dir = paths::mod_root().join(&m.id);
    let result: Result<()> = (|| {
        // Store, then module dir (staging + rename).
        store::store_payload(&m.id, &m.version, &payload.dir)?;
        let staging = paths::mod_root().join(format!(".staging-{}", m.id));
        if staging.exists() {
            std::fs::remove_dir_all(&staging)?;
        }
        std::fs::create_dir_all(paths::mod_root())?;
        store::copy_tree(&payload.dir, &staging)?;
        if module_dir.exists() {
            std::fs::remove_dir_all(&module_dir)?;
        }
        std::fs::rename(&staging, &module_dir)?;

        // Pristine snapshots (first touch), then recompose stock files.
        for rel in &stock_targets {
            let target = ii.join(rel);
            if target.exists() {
                let current = std::fs::read_to_string(&target)?;
                let (stripped, _) = patch::strip(&current)?;
                store::ensure_pristine_snapshot(rel, &stripped)?;
            }
        }
        std::fs::create_dir_all(paths::host_dir())?;
        recompose_all(&next, true)?;
        std::fs::write(
            paths::host_dir().join("ModuleHost.qml"),
            include_str!("../assets/ModuleHost.qml"),
        )?;
        std::fs::write(
            paths::host_dir().join("ModulesConfig.qml"),
            include_str!("../assets/ModulesConfig.qml"),
        )?;
        hostpatch::write_module_imports(&module_import_ids(&next))?;
        let sentinel = hostpatch::HostSentinel {
            host_version: hostpatch::HOST_VERSION.to_string(),
            protocol_version: manifest::SUPPORTED_PROTOCOL_MAX,
            installed_at_epoch: registry::now_epoch(),
            qs_version_hint: qs::qs_version(),
        };
        std::fs::write(
            paths::host_sentinel(),
            serde_json::to_string_pretty(&sentinel)? + "\n",
        )?;
        std::fs::create_dir_all(paths::modules_config_dir())?;

        // Translations.
        let mut warn = Vec::new();
        let owned = translations::merge(&registry, &m.id, &module_dicts, &mut warn)?;
        for w in warn {
            eprintln!("warning: {w}");
        }
        next.get_mut(&m.id).unwrap().translation_keys = owned;
        Ok(())
    })();

    if let Err(e) = result {
        // Rollback: shell.qml first, then the rest; remove module dir.
        eprintln!("install failed — rolling back: {e}");
        let _ = backups.restore("stock/shell.qml", &ii.join("shell.qml"));
        for rel in &stock_targets {
            if rel != "shell.qml" {
                let _ = backups.restore(&format!("stock/{rel}"), &ii.join(rel));
            }
        }
        let _ = backups.restore(
            "config.json",
            &paths::shell_config_root().join("config.json"),
        );
        for locale in module_dicts.keys() {
            let _ = backups.restore(
                &format!("translations/{locale}.json"),
                &paths::translations_dir().join(format!("{locale}.json")),
            );
        }
        if module_dir.exists() {
            let _ = std::fs::remove_dir_all(&module_dir);
        }
        let _ = std::fs::remove_file(paths::journal_path());
        return Err(e);
    }

    // Commit.
    next.host_version = Some(hostpatch::HOST_VERSION.to_string());
    if opts.no_enable {
        next.get_mut(&m.id).unwrap().state = ModuleState::Disabled;
    }
    registry::save(&next)?;
    write_index_projection(&next)?;
    project_enabled(&next)?;
    let _ = std::fs::remove_file(paths::journal_path());
    store::prune_backups(10)?;

    if !qs::trigger_reload() {
        eprintln!("note: could not trigger a shell reload (shell not running?) — changes apply on next start");
    } else if !qs::disabled() {
        // First-install race guard: a pre-reload shell instance (whose adapter
        // did not declare `iimp` yet) can erase the direct config.json write.
        // After the reload, reconcile once more through the host IPC.
        std::thread::sleep(std::time::Duration::from_millis(1500));
        if qs::ping() {
            project_enabled(&next)?;
        }
    }
    if let Some(old) = upgrading {
        println!("✓ upgraded {} {} → {}", m.id, old, m.version);
    } else {
        println!(
            "✓ installed {} v{}{}",
            m.id,
            m.version,
            if opts.no_enable { " (disabled)" } else { "" }
        );
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// uninstall / enable / disable
// ---------------------------------------------------------------------------

pub fn cmd_uninstall(id: &str, cascade: bool) -> Result<()> {
    let _lock = Lock::acquire()?;
    let mut registry = registry::load()?;
    if registry.get(id).is_none() {
        return Err(bail(exit::USAGE, format!("module {id:?} is not installed")));
    }
    let mut victims = registry.dependent_closure(id);
    if !victims.is_empty() && !cascade {
        return Err(bail(
            exit::DEPENDENCY,
            format!("modules depend on {id:?}: {victims:?}\nremove them first or pass --cascade"),
        ));
    }
    victims.push(id.to_string());
    // Reverse topological: dependents before dependencies.
    let topo = registry.topological_order()?;
    victims.sort_by_key(|v| std::cmp::Reverse(topo.iter().position(|t| t == v)));
    println!("removing: {victims:?}");

    let ii = paths::ii_root();
    for victim in &victims {
        let module = registry.remove(victim).expect("present");
        let dicts_dir = paths::store_dir()
            .join(victim)
            .join(&module.manifest.version);
        let dicts = translations::load_module_dicts(&dicts_dir).unwrap_or_default();
        translations::unmerge(&dicts, &module.translation_keys)?;
        let dir = paths::mod_root().join(victim);
        if dir.exists() {
            std::fs::remove_dir_all(&dir)?;
        }
        store::remove_from_store(victim)?;
    }
    recompose_all(&registry, true)?;
    if paths::host_dir().exists() {
        hostpatch::write_module_imports(&module_import_ids(&registry))?;
    }
    registry::save(&registry)?;
    write_index_projection(&registry)?;
    project_enabled(&registry)?;
    let _ = qs::trigger_reload();
    let _ = ii;
    println!("✓ uninstalled");
    Ok(())
}

pub fn cmd_set_state(id: &str, enable: bool) -> Result<()> {
    let _lock = Lock::acquire()?;
    let mut registry = registry::load()?;
    let Some(module) = registry.get(id) else {
        return Err(bail(exit::USAGE, format!("module {id:?} is not installed")));
    };
    if matches!(module.state, ModuleState::Incompatible) {
        return Err(bail(
            exit::STATE,
            format!("{id:?} is marked incompatible (reapply reported failing probes)"),
        ));
    }

    let mut to_flip = vec![id.to_string()];
    if enable {
        // Auto-enable installed dependency closure.
        let mut frontier = vec![id.to_string()];
        while let Some(current) = frontier.pop() {
            let deps: Vec<String> = registry
                .get(&current)
                .map(|m| {
                    m.manifest
                        .requires
                        .modules
                        .iter()
                        .map(|d| d.id.clone())
                        .collect()
                })
                .unwrap_or_default();
            for dep in deps {
                if registry.get(&dep).is_none() {
                    return Err(bail(
                        exit::DEPENDENCY,
                        format!("dependency {dep:?} is not installed (wiped? run reapply)"),
                    ));
                }
                if !to_flip.contains(&dep) {
                    to_flip.push(dep.clone());
                    frontier.push(dep);
                }
            }
        }
    } else {
        to_flip.extend(registry.dependent_closure(id));
    }
    for target in &to_flip {
        if let Some(m) = registry.get_mut(target) {
            if !matches!(
                m.state,
                ModuleState::Incompatible | ModuleState::BlockedByDep
            ) {
                m.state = if enable {
                    ModuleState::Enabled
                } else {
                    ModuleState::Disabled
                };
            }
        }
    }
    registry::save(&registry)?;
    write_index_projection(&registry)?;
    project_enabled(&registry)?;
    println!(
        "✓ {} {:?}",
        if enable { "enabled" } else { "disabled" },
        to_flip
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// list / info
// ---------------------------------------------------------------------------

pub fn cmd_list() -> Result<()> {
    let registry = registry::load()?;
    wipe_banner(&registry);
    if registry.modules.is_empty() {
        println!("no modules installed");
        return Ok(());
    }
    for m in &registry.modules {
        println!(
            "{:<24} v{:<10} {:?}  slots={:?}{}",
            m.manifest.id,
            m.manifest.version,
            m.state,
            m.manifest.slots,
            if m.manifest.is_tier_b() {
                "  [Tier B]"
            } else {
                ""
            }
        );
    }
    Ok(())
}

pub fn cmd_info(id: &str) -> Result<()> {
    let registry = registry::load()?;
    let Some(m) = registry.get(id) else {
        return Err(bail(exit::USAGE, format!("module {id:?} is not installed")));
    };
    println!("{}", serde_json::to_string_pretty(&m)?);
    Ok(())
}

// ---------------------------------------------------------------------------
// pack / init
// ---------------------------------------------------------------------------

pub fn cmd_pack(payload: &Path, out: Option<PathBuf>) -> Result<()> {
    let (m, warnings) = validate_payload(payload)?;
    for w in warnings {
        eprintln!("warning: {w}");
    }
    let out = out.unwrap_or_else(|| PathBuf::from(format!("{}-{}.iimod", m.id, m.version)));
    pkg::pack(payload, &m.id, &out)?;
    println!("✓ packed {} v{} → {}", m.id, m.version, out.display());
    Ok(())
}

pub fn cmd_init(id: &str, dir: &Path) -> Result<()> {
    if !manifest::is_valid_id(id) || manifest::RESERVED_IDS.contains(&id) {
        return Err(bail(exit::USAGE, format!("invalid module id {id:?}")));
    }
    let payload = dir.join(id);
    if payload.exists() {
        return Err(bail(
            exit::USAGE,
            format!("{} already exists", payload.display()),
        ));
    }
    std::fs::create_dir_all(payload.join("translations"))?;
    let manifest = serde_json::json!({
        "protocolVersion": 1,
        "id": id,
        "name": {"en_US": id},
        "description": {"en_US": "TODO: describe this module."},
        "version": "0.1.0",
        "authors": ["TODO"],
        "license": "MIT",
        "slots": ["bar"],
        "compat": {
            "probes": [
                {"type": "file-exists", "path": "modules/ii/bar/BarGroup.qml", "reason": "bar container widget"}
            ]
        },
        "capabilities": []
    });
    std::fs::write(
        payload.join("module.json"),
        serde_json::to_string_pretty(&manifest)? + "\n",
    )?;
    std::fs::write(
        payload.join("bar.qml"),
        format!(
            "import QtQuick\nimport QtQuick.Layouts\nimport qs.modules.common\nimport qs.modules.common.widgets\n// import qs.mod.{id}   // ← uncomment when you add sibling .qml components\n\n"
        ) + concat!(
            "// Bar slot entry: MUST root a visual Item.\n",
            "MouseArea {\n",
            "    id: root\n",
            "    implicitWidth: label.implicitWidth + 10 * 2\n",
            "    implicitHeight: Appearance.sizes.barHeight\n",
            "    hoverEnabled: !Config.options.bar.tooltips.clickToShow\n\n",
            "    StyledText {\n",
            "        id: label\n",
            "        anchors.centerIn: parent\n",
            "        color: Appearance.colors.colOnLayer1\n",
            "        text: \"hello\"\n",
            "    }\n",
            "}\n",
        ),
    )?;
    std::fs::write(payload.join("translations/zh_TW.json"), "{}\n")?;
    std::fs::write(
        payload.join("README.md"),
        format!("# {id}\n\nAn IIMP module. Develop with:\n\n```\niimod validate {id}/\niimod check {id}/\niimod install {id}/\n```\n"),
    )?;
    println!("✓ scaffolded {}", payload.display());
    Ok(())
}

// ---------------------------------------------------------------------------
// suggest
// ---------------------------------------------------------------------------

pub fn cmd_suggest(source: &Path, max_size: u64) -> Result<()> {
    let payload = load_payload(source, max_size)?;
    let suggestions = lint::suggest(&payload.dir, &paths::ii_root())?;

    // Compare against the manifest when present (may be a work in progress).
    let manifest: Option<Manifest> = std::fs::read(payload.dir.join("module.json"))
        .ok()
        .and_then(|b| manifest::parse(&b).ok());

    println!("── suggested compat.probes ──");
    if suggestions.probes.is_empty() {
        println!("  (none — only guaranteed-baseline APIs detected)");
    }
    for (path, reason) in &suggestions.probes {
        let already = manifest
            .as_ref()
            .is_some_and(|m| m.compat.probes.iter().any(|p| p.path == *path));
        println!(
            "  {} {{\"type\": \"file-exists\", \"path\": \"{path}\", \"reason\": \"{reason}\"}}",
            if already { "✓(declared)" } else { "+" }
        );
    }

    println!("── suggested capabilities ──");
    if suggestions.capabilities.is_empty() {
        println!("  []");
    }
    for cap in &suggestions.capabilities {
        let already = manifest
            .as_ref()
            .is_some_and(|m| m.capabilities.contains(cap));
        println!("  {} {:?}", if already { "✓(declared)" } else { "+" }, cap);
    }

    for note in &suggestions.notes {
        println!("note: {note}");
    }
    println!("\nsuggestions are heuristics — review before pasting into module.json");
    Ok(())
}

// ---------------------------------------------------------------------------
// verify / repair
// ---------------------------------------------------------------------------

fn module_file_state(m: &InstalledModule) -> &'static str {
    let dir = paths::mod_root().join(&m.manifest.id);
    if !dir.exists() {
        return "missing";
    }
    match store::hash_tree(&dir) {
        Ok(actual) if actual == m.files => "intact",
        Ok(_) => "module-modified",
        Err(_) => "missing",
    }
}

pub fn cmd_verify() -> Result<()> {
    let registry = registry::load()?;
    if wipe_banner(&registry) {
        for m in &registry.modules {
            println!("{:<24} wiped", m.manifest.id);
        }
        return Err(bail(exit::STATE, "shell tree wiped — run: iimod reapply"));
    }
    let ii = paths::ii_root();
    let mut bad = 0;

    for m in &registry.modules {
        let mut state = module_file_state(m).to_string();
        if state == "intact" {
            for rel in m.patch_records.keys() {
                let target = ii.join(rel);
                let current = std::fs::read_to_string(&target).unwrap_or_default();
                match patch::strip(&current) {
                    Err(_) => {
                        state = "fence-broken".into();
                        break;
                    }
                    Ok((stripped, _)) => {
                        if let Some(pristine) = store::read_pristine(rel) {
                            if stripped != pristine {
                                state = "stock-drifted".into();
                            }
                        }
                        let expected =
                            patch::compose(&stripped, &full_patch_set(&registry, rel, None))?;
                        if expected != current {
                            state = "fence-broken".into();
                            break;
                        }
                    }
                }
            }
        }
        if state != "intact" {
            bad += 1;
        }
        println!("{:<24} {}", m.manifest.id, state);
    }

    // Host integrity.
    let host_state = if hostpatch::read_sentinel().is_none() && !registry.modules.is_empty() {
        "wiped"
    } else if hostpatch::host_files_present() || registry.modules.is_empty() {
        "intact"
    } else {
        "missing"
    };
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

pub fn cmd_repair(id: Option<&str>) -> Result<()> {
    let _lock = Lock::acquire()?;
    let registry = registry::load()?;
    if let Some(id) = id {
        let Some(m) = registry.get(id) else {
            return Err(bail(exit::USAGE, format!("module {id:?} is not installed")));
        };
        let src = store::store_path(id, &m.manifest.version);
        let dest = paths::mod_root().join(id);
        if dest.exists() {
            std::fs::remove_dir_all(&dest)?;
        }
        store::copy_tree(&src, &dest)?;
    }
    hostpatch::ensure_host(&|rel| registry.patches_for_file(rel))?;
    hostpatch::write_module_imports(&module_import_ids(&registry))?;
    recompose_all(&registry, true)?;
    write_index_projection(&registry)?;
    let _ = qs::trigger_reload();
    println!("✓ repaired");
    Ok(())
}

// ---------------------------------------------------------------------------
// reapply
// ---------------------------------------------------------------------------

pub fn cmd_reapply() -> Result<()> {
    let _lock = Lock::acquire()?;
    let mut registry = registry::load()?;
    if registry.modules.is_empty() {
        println!("no modules installed; ensuring host only if previously present");
        if registry.host_version.is_some() {
            hostpatch::ensure_host(&|_| Vec::new())?;
        }
        return Ok(());
    }

    let ii = paths::ii_root();
    let order = registry.topological_order()?;
    let mut incompatible: Vec<(String, String)> = Vec::new();

    // 1. Probe every module against the (possibly updated) stock tree.
    for id in &order {
        let m = registry.get(id).unwrap();
        let failures = probe::evaluate(&ii, &m.manifest.compat.probes);
        let blocked_dep = m
            .manifest
            .requires
            .modules
            .iter()
            .any(|d| incompatible.iter().any(|(bad, _)| bad == &d.id));
        if !failures.is_empty() {
            let reason = failures
                .iter()
                .map(|f| format!("{} ({})", f.probe.path, f.probe.reason))
                .collect::<Vec<_>>()
                .join("; ");
            incompatible.push((id.clone(), reason));
            registry.get_mut(id).unwrap().state = ModuleState::Incompatible;
        } else if blocked_dep {
            incompatible.push((id.clone(), "blocked by incompatible dependency".into()));
            registry.get_mut(id).unwrap().state = ModuleState::BlockedByDep;
        } else if matches!(
            registry.get(id).unwrap().state,
            ModuleState::Incompatible | ModuleState::BlockedByDep
        ) {
            // Previously incompatible, now probing clean → re-enable as disabled
            // (user opts back in explicitly).
            registry.get_mut(id).unwrap().state = ModuleState::Disabled;
        }
    }

    // 2. Refresh pristine snapshots from the new stock tree (fence-stripped).
    for rel in all_stock_targets(&registry, &[]) {
        let target = ii.join(&rel);
        if target.exists() {
            let current = std::fs::read_to_string(&target)?;
            if let Ok((stripped, _)) = patch::strip(&current) {
                store::refresh_pristine_snapshot(&rel, &stripped)?;
            }
        }
    }

    // 3. Mirror store payloads back into $II/mod/.
    for id in &order {
        let m = registry.get(id).unwrap();
        if matches!(
            m.state,
            ModuleState::Incompatible | ModuleState::BlockedByDep
        ) {
            continue;
        }
        let src = store::store_path(id, &m.manifest.version);
        if !src.exists() {
            registry.get_mut(id).unwrap().state = ModuleState::Incompatible;
            incompatible.push((id.clone(), "store payload missing".into()));
            continue;
        }
        let dest = paths::mod_root().join(id);
        if dest.exists() {
            std::fs::remove_dir_all(&dest)?;
        }
        store::copy_tree(&src, &dest)?;
    }

    // 4. Recompose all stock files (anchor failure → mark incompatible, retry once).
    for _attempt in 0..2 {
        match hostpatch::ensure_host(&|rel| registry.patches_for_file(rel)) {
            Ok(_) => break,
            Err(e) if exit::code_of(&e) == exit::ANCHOR => {
                // Identify the failing owner from the message and downgrade it.
                let msg = format!("{e}");
                let owner = registry
                    .modules
                    .iter()
                    .map(|m| m.manifest.id.clone())
                    .find(|id| msg.contains(&format!("{id}/")));
                match owner {
                    Some(id) => {
                        incompatible.push((id.clone(), format!("anchor failure: {msg}")));
                        registry.get_mut(&id).unwrap().state = ModuleState::Incompatible;
                    }
                    None => return Err(e), // host anchor failed — upstream moved it
                }
            }
            Err(e) => return Err(e),
        }
    }

    // 5. Translations re-merge for surviving modules.
    for id in &order {
        let m = registry.get(id).unwrap().clone();
        if matches!(
            m.state,
            ModuleState::Incompatible | ModuleState::BlockedByDep
        ) {
            continue;
        }
        let store_payload = store::store_path(id, &m.manifest.version);
        let dicts = translations::load_module_dicts(&store_payload).unwrap_or_default();
        let mut warn = Vec::new();
        let owned = translations::merge(&registry, id, &dicts, &mut warn)?;
        registry.get_mut(id).unwrap().translation_keys = owned;
    }

    hostpatch::write_module_imports(&module_import_ids(&registry))?;
    registry.host_version = Some(hostpatch::HOST_VERSION.to_string());
    registry::save(&registry)?;
    write_index_projection(&registry)?;
    project_enabled(&registry)?;
    let _ = qs::trigger_reload();

    if incompatible.is_empty() {
        println!("✓ reapplied all modules");
    } else {
        println!(
            "reapplied with {} module(s) disabled as incompatible:",
            incompatible.len()
        );
        for (id, reason) in &incompatible {
            println!("  ✗ {id}: {reason}");
        }
        println!("they stay disabled until updated versions pass their probes");
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// doctor
// ---------------------------------------------------------------------------

pub fn cmd_doctor(rebuild_registry: bool) -> Result<()> {
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

    if rebuild_registry {
        let mut rebuilt = Registry::default();
        if let Ok(entries) = std::fs::read_dir(paths::store_dir()) {
            for entry in entries.flatten() {
                let id = entry.file_name().to_string_lossy().into_owned();
                let Ok(versions) = std::fs::read_dir(entry.path()) else {
                    continue;
                };
                let mut best: Option<(semver::Version, PathBuf)> = None;
                for v in versions.flatten() {
                    if let Ok(parsed) = semver::Version::parse(&v.file_name().to_string_lossy()) {
                        if best.as_ref().is_none_or(|(b, _)| parsed > *b) {
                            best = Some((parsed, v.path()));
                        }
                    }
                }
                if let Some((_, payload)) = best {
                    if let Ok((m, _)) = validate_payload(&payload) {
                        let mut patch_records: BTreeMap<String, Vec<PatchInstance>> =
                            BTreeMap::new();
                        for (i, p) in m.patches.iter().enumerate() {
                            patch_records
                                .entry(p.file.clone())
                                .or_default()
                                .push(PatchInstance {
                                    owner: m.id.clone(),
                                    index: i as u32,
                                    version: m.version.clone(),
                                    op: p.op,
                                    anchor: p.anchor.clone(),
                                    content: p.content.clone(),
                                });
                        }
                        rebuilt.modules.push(InstalledModule {
                            files: store::hash_tree(&payload)?,
                            manifest: m,
                            state: ModuleState::Disabled,
                            patch_records,
                            translation_keys: BTreeMap::new(),
                            installed_at_epoch: registry::now_epoch(),
                        });
                        println!("recovered from store: {id}");
                    }
                }
            }
        }
        registry::save(&rebuilt)?;
        println!(
            "✓ registry rebuilt ({} modules, all disabled — enable + reapply as needed)",
            rebuilt.modules.len()
        );
        return Ok(());
    }

    match registry::load() {
        Ok(registry) => {
            println!("registry: ok ({} modules)", registry.modules.len());
            wipe_banner(&registry);
            let sentinel = hostpatch::read_sentinel();
            match sentinel {
                Some(s) => println!(
                    "host: v{} (installed {})",
                    s.host_version, s.installed_at_epoch
                ),
                None => println!("host: not installed"),
            }
        }
        Err(e) => println!("registry: CORRUPT ({e}) — run: iimod doctor --rebuild-registry"),
    }
    Ok(())
}
