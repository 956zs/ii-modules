//! Install transaction: validate, dry-run, mutate, rollback, and commit.

use std::collections::BTreeMap;
use std::path::Path;
use std::time::Duration;

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::manifest::{self, Manifest};
use crate::ops::{
    all_stock_targets, check_deps_conflicts, full_patch_set, load_payload, module_import_ids,
    patch_records_for, project_enabled, recompose_all, validate_payload, wipe_banner,
    write_index_projection, Payload, HOST_FILES,
};
use crate::patch::{self, PatchInstance};
use crate::paths;
use crate::probe;
use crate::qs;
use crate::registry::{self, InstalledModule, Lock, ModuleState, Registry};
use crate::store::{self, BackupSet};
use crate::translations;

const RELOAD_RECONCILE_DELAY_MS: u64 = 1500;
const BACKUPS_TO_KEEP: usize = 10;

type ModuleDicts = BTreeMap<String, BTreeMap<String, String>>;
type PatchRecords = BTreeMap<String, Vec<PatchInstance>>;

pub struct InstallOpts {
    pub allow_patches: bool,
    pub reinstall: bool,
    pub no_enable: bool,
    pub max_size: u64,
    /// Update index URL to record; None preserves an existing record's origin.
    pub origin: Option<String>,
}

struct InstallCandidate {
    payload: Payload,
    manifest: Manifest,
    patch_records: PatchRecords,
}

struct PreparedInstall {
    registry: Registry,
    next: Registry,
    candidate: InstallCandidate,
    module_dicts: ModuleDicts,
    stock_targets: Vec<String>,
    module_dir: std::path::PathBuf,
    upgrading: Option<String>,
}

enum InstallReadiness {
    AlreadyCurrent,
    Proceed { upgrading: Option<String> },
}

pub fn cmd_install(source: &Path, opts: &InstallOpts) -> Result<()> {
    let _lock = Lock::acquire()?;
    let registry = registry::load()?;
    reject_wiped_tree(&registry)?;

    let Some(mut prepared) = prepare_install(source, opts, registry)? else {
        return Ok(());
    };
    let backups = begin_install_journal(&prepared)?;
    let result = apply_install_mutation(&mut prepared);
    if let Err(e) = result {
        eprintln!("install failed — rolling back: {e}");
        rollback_install(&prepared, &backups);
        return Err(e);
    }
    commit_install(prepared, opts)
}

fn reject_wiped_tree(registry: &Registry) -> Result<()> {
    if !wipe_banner(registry) {
        return Ok(());
    }
    Err(bail(
        exit::STATE,
        "shell tree is wiped; run `iimod reapply` before installing",
    ))
}

fn prepare_install(
    source: &Path,
    opts: &InstallOpts,
    registry: Registry,
) -> Result<Option<PreparedInstall>> {
    let candidate = load_candidate(source, opts.max_size)?;
    let readiness = assess_candidate(&candidate, &registry, opts)?;
    let upgrading = match readiness {
        InstallReadiness::AlreadyCurrent => return Ok(None),
        InstallReadiness::Proceed { upgrading } => upgrading,
    };
    let next = registry_with_candidate(&registry, &candidate, opts.origin.as_deref())?;
    dry_run_stock_composition(&next)?;
    let module_dicts = translations::load_module_dicts(&candidate.payload.dir)?;
    let stock_targets = all_stock_targets(&next, &[]);
    let module_dir = paths::mod_root().join(&candidate.manifest.id);

    Ok(Some(PreparedInstall {
        registry,
        next,
        candidate,
        module_dicts,
        stock_targets,
        module_dir,
        upgrading,
    }))
}

fn load_candidate(source: &Path, max_size: u64) -> Result<InstallCandidate> {
    let payload = load_payload(source, max_size)?;
    let (manifest, warnings) = validate_payload(&payload.dir)?;
    for w in &warnings {
        eprintln!("warning: {w}");
    }
    if !payload.from_package {
        eprintln!(
            "note: installing from a directory (developer mode) — no package integrity check"
        );
    }
    let patch_records = patch_records_for(&manifest);
    Ok(InstallCandidate {
        payload,
        manifest,
        patch_records,
    })
}

fn assess_candidate(
    candidate: &InstallCandidate,
    registry: &Registry,
    opts: &InstallOpts,
) -> Result<InstallReadiness> {
    let manifest = &candidate.manifest;
    let upgrading = match registry.get(&manifest.id) {
        Some(existing) if existing.manifest.version == manifest.version && !opts.reinstall => {
            println!(
                "{} v{} already installed (use --reinstall to force)",
                manifest.id, manifest.version
            );
            return Ok(InstallReadiness::AlreadyCurrent);
        }
        Some(existing) => Some(existing.manifest.version.clone()),
        None => None,
    };

    check_deps_conflicts(manifest, registry)?;
    probe::require(&paths::ii_root(), &manifest.compat.probes)?;
    require_patch_permission(manifest, opts)?;
    Ok(InstallReadiness::Proceed { upgrading })
}

fn require_patch_permission(manifest: &Manifest, opts: &InstallOpts) -> Result<()> {
    if !manifest.is_tier_b() || opts.allow_patches {
        return Ok(());
    }
    let files: Vec<&str> = manifest.patches.iter().map(|p| p.file.as_str()).collect();
    Err(bail(
        exit::NEEDS_ALLOW_PATCHES,
        format!(
            "{} is a Tier B module: it modifies stock files {:?}.\nReview manifest patches[] and capabilities, then re-run with --allow-patches",
            manifest.id, files
        ),
    ))
}

fn registry_with_candidate(
    registry: &Registry,
    candidate: &InstallCandidate,
    origin: Option<&str>,
) -> Result<Registry> {
    let mut next = registry.clone();
    // Upgrades keep their update origin unless the caller supplies a new one.
    let origin = origin
        .map(str::to_string)
        .or_else(|| next.get(&candidate.manifest.id).and_then(|m| m.origin.clone()));
    next.remove(&candidate.manifest.id);
    // The generated qmldir is part of the installed tree, so it must be part
    // of the recorded hash set or verify would flag every module.
    let mut files = store::hash_tree(&candidate.payload.dir)?;
    if let Some(content) = store::qmldir_content(&candidate.manifest.id, &candidate.payload.dir)? {
        files.insert("qmldir".into(), store::sha256_bytes(content.as_bytes()));
    }
    next.modules.push(InstalledModule {
        manifest: candidate.manifest.clone(),
        state: ModuleState::Enabled,
        files,
        patch_records: candidate.patch_records.clone(),
        translation_keys: BTreeMap::new(),
        installed_at_epoch: registry::now_epoch(),
        origin,
    });
    Ok(next)
}

fn dry_run_stock_composition(registry: &Registry) -> Result<()> {
    let ii = paths::ii_root();
    for rel in all_stock_targets(registry, &[]) {
        let target = ii.join(&rel);
        if target.exists() {
            let current = std::fs::read_to_string(&target)?;
            patch::recompose(&current, &full_patch_set(registry, &rel, None))?;
        } else if HOST_FILES.contains(&rel.as_str()) {
            return Err(bail(exit::STATE, format!("stock file missing: {rel}")));
        } else {
            return Err(bail(exit::ANCHOR, format!("patch target missing: {rel}")));
        }
    }
    Ok(())
}

fn begin_install_journal(prepared: &PreparedInstall) -> Result<BackupSet> {
    let backups = BackupSet::create()?;
    let ii = paths::ii_root();
    for rel in &prepared.stock_targets {
        backups.add(&format!("stock/{rel}"), &ii.join(rel))?;
    }
    backups.add(
        "config.json",
        &paths::shell_config_root().join("config.json"),
    )?;
    for locale in prepared.module_dicts.keys() {
        backups.add(
            &format!("translations/{locale}.json"),
            &paths::translations_dir().join(format!("{locale}.json")),
        )?;
    }
    write_install_journal(prepared, &backups)?;
    Ok(backups)
}

fn write_install_journal(prepared: &PreparedInstall, backups: &BackupSet) -> Result<()> {
    let manifest = &prepared.candidate.manifest;
    std::fs::write(
        paths::journal_path(),
        serde_json::to_string_pretty(&serde_json::json!({
            "op": "install",
            "id": &manifest.id,
            "version": &manifest.version,
            "backups": &backups.dir,
            "stockTargets": &prepared.stock_targets,
        }))? + "\n",
    )?;
    Ok(())
}

fn apply_install_mutation(prepared: &mut PreparedInstall) -> Result<()> {
    stage_module_payload(prepared)?;
    refresh_pristine_snapshots(prepared)?;
    std::fs::create_dir_all(paths::host_dir())?;
    recompose_all(&prepared.next, true)?;
    write_host_assets(&prepared.next)?;
    merge_install_translations(prepared)?;
    Ok(())
}

fn stage_module_payload(prepared: &PreparedInstall) -> Result<()> {
    let manifest = &prepared.candidate.manifest;
    store::store_payload(
        &manifest.id,
        &manifest.version,
        &prepared.candidate.payload.dir,
    )?;
    let staging = paths::mod_root().join(format!(".staging-{}", manifest.id));
    if staging.exists() {
        std::fs::remove_dir_all(&staging)?;
    }
    std::fs::create_dir_all(paths::mod_root())?;
    store::copy_tree(&prepared.candidate.payload.dir, &staging)?;
    store::write_qmldir(&manifest.id, &staging)?;
    if prepared.module_dir.exists() {
        std::fs::remove_dir_all(&prepared.module_dir)?;
    }
    std::fs::rename(&staging, &prepared.module_dir)?;
    Ok(())
}

fn refresh_pristine_snapshots(prepared: &PreparedInstall) -> Result<()> {
    let ii = paths::ii_root();
    for rel in &prepared.stock_targets {
        let target = ii.join(rel);
        if target.exists() {
            let current = std::fs::read_to_string(&target)?;
            let (stripped, _) = patch::strip(&current)?;
            store::ensure_pristine_snapshot(rel, &stripped)?;
        }
    }
    Ok(())
}

fn write_host_assets(registry: &Registry) -> Result<()> {
    std::fs::write(
        paths::host_dir().join("ModuleHost.qml"),
        include_str!("../assets/ModuleHost.qml"),
    )?;
    std::fs::write(
        paths::host_dir().join("ModulesConfig.qml"),
        include_str!("../assets/ModulesConfig.qml"),
    )?;
    hostpatch::write_module_imports(&module_import_ids(registry))?;
    write_host_sentinel()?;
    std::fs::create_dir_all(paths::modules_config_dir())?;
    Ok(())
}

fn write_host_sentinel() -> Result<()> {
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
    Ok(())
}

fn merge_install_translations(prepared: &mut PreparedInstall) -> Result<()> {
    let id = prepared.candidate.manifest.id.clone();
    let mut warn = Vec::new();
    let owned = translations::merge(&prepared.registry, &id, &prepared.module_dicts, &mut warn)?;
    for w in warn {
        eprintln!("warning: {w}");
    }
    prepared.next.get_mut(&id).unwrap().translation_keys = owned;
    Ok(())
}

fn rollback_install(prepared: &PreparedInstall, backups: &BackupSet) {
    let ii = paths::ii_root();
    let _ = backups.restore("stock/shell.qml", &ii.join("shell.qml"));
    for rel in &prepared.stock_targets {
        if rel != "shell.qml" {
            let _ = backups.restore(&format!("stock/{rel}"), &ii.join(rel));
        }
    }
    let _ = backups.restore(
        "config.json",
        &paths::shell_config_root().join("config.json"),
    );
    for locale in prepared.module_dicts.keys() {
        let _ = backups.restore(
            &format!("translations/{locale}.json"),
            &paths::translations_dir().join(format!("{locale}.json")),
        );
    }
    if prepared.module_dir.exists() {
        let _ = std::fs::remove_dir_all(&prepared.module_dir);
    }
    let _ = std::fs::remove_file(paths::journal_path());
}

fn commit_install(mut prepared: PreparedInstall, opts: &InstallOpts) -> Result<()> {
    prepared.next.host_version = Some(hostpatch::HOST_VERSION.to_string());
    if opts.no_enable {
        let id = prepared.candidate.manifest.id.clone();
        prepared.next.get_mut(&id).unwrap().state = ModuleState::Disabled;
    }
    registry::save(&prepared.next)?;
    project_new_state(&prepared.next)?;
    store::prune_backups(BACKUPS_TO_KEEP)?;
    reload_and_reconcile(&prepared.next)?;
    print_install_result(&prepared, opts);
    Ok(())
}

fn project_new_state(registry: &Registry) -> Result<()> {
    write_index_projection(registry)?;
    project_enabled(registry)?;
    let _ = std::fs::remove_file(paths::journal_path());
    Ok(())
}

fn reload_and_reconcile(registry: &Registry) -> Result<()> {
    if !qs::trigger_reload() {
        eprintln!("note: could not trigger a shell reload (shell not running?) — changes apply on next start");
        return Ok(());
    }
    if qs::disabled() {
        return Ok(());
    }
    std::thread::sleep(Duration::from_millis(RELOAD_RECONCILE_DELAY_MS));
    if qs::ping() {
        project_enabled(registry)?;
    }
    Ok(())
}

fn print_install_result(prepared: &PreparedInstall, opts: &InstallOpts) {
    let manifest = &prepared.candidate.manifest;
    if let Some(old) = &prepared.upgrading {
        println!("✓ upgraded {} {} → {}", manifest.id, old, manifest.version);
    } else {
        println!(
            "✓ installed {} v{}{}",
            manifest.id,
            manifest.version,
            if opts.no_enable { " (disabled)" } else { "" }
        );
    }
}
