//! Install transaction: validate, dry-run, mutate, rollback, and commit.

use std::collections::BTreeMap;
use std::path::Path;
use std::time::Duration;

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::hoststate::{self, HostBundle, MutationMode};
use crate::manifest::Manifest;
use crate::ops::{
    all_stock_targets, check_deps_conflicts, full_patch_set, load_payload, module_import_ids,
    patch_records_for, project_enabled, recompose_all, validate_payload, wipe_banner,
    write_index_projection, Payload, HOST_FILES,
};
use crate::patch::{self, PatchInstance};
use crate::paths;
use crate::probe;
use crate::qs;
use crate::registry::{self, InstalledModule, ModuleState, Registry};
use crate::store::{self, BackupSet};
use crate::translations;

const RELOAD_RECONCILE_DELAY_MS: u64 = 1500;
const BACKUPS_TO_KEEP: usize = 10;

type ModuleDicts = BTreeMap<String, BTreeMap<String, String>>;
type PatchRecords = BTreeMap<String, Vec<PatchInstance>>;

#[derive(Clone)]
pub struct InstallOpts {
    pub allow_patches: bool,
    pub reinstall: bool,
    pub no_enable: bool,
    pub max_size: u64,
    /// Update index URL to record; None preserves an existing record's origin.
    pub origin: Option<String>,
    /// Sibling-index guess from a URL install; weakest precedence.
    pub derived_origin: Option<String>,
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
    // URL sources: download first, and default the update origin to the
    // sibling index.json so `iimod update` works with nothing typed —
    // publishers keep an index.json next to their packages (GitHub Releases'
    // latest/download/ satisfies this for free).
    let mut opts = opts.clone();
    let downloaded: Option<std::path::PathBuf>;
    let source: &Path = match source.to_str() {
        Some(url) if url.starts_with("https://") || url.starts_with("file://") => {
            let name = url.rsplit('/').next().unwrap_or("package.iimod");
            if !name.ends_with(".iimod") {
                return Err(bail(
                    exit::USAGE,
                    format!("URL install expects a .iimod package, got {name:?}"),
                ));
            }
            let dir = paths::tmp_dir().join(format!(
                "fetch-{}-{}",
                registry::now_epoch(),
                std::process::id()
            ));
            std::fs::create_dir_all(&dir)?;
            let file = dir.join(name);
            crate::update::curl_fetch(url, &file, opts.max_size)?;
            // Sibling-index guess; outranked by --origin and by an origin
            // embedded in the package (the publisher's canonical statement).
            if let Some(i) = url.rfind('/') {
                opts.derived_origin = Some(format!("{}/index.json", &url[..i]));
            }
            downloaded = Some(file);
            downloaded.as_deref().unwrap()
        }
        _ => source,
    };
    let opts = &opts;

    let mutation = hoststate::mutation_preflight(MutationMode::Normal)?;
    let registry = registry::load()?;
    reject_wiped_tree(&registry)?;

    let Some(mut prepared) = prepare_install(source, opts, registry, mutation.host())? else {
        return Ok(());
    };
    let backups = begin_install_journal(&prepared)?;
    let result = apply_install_mutation(&mut prepared, mutation.host())
        .and_then(|_| mutation.activate_after_host_write())
        .and_then(|_| commit_install(&mut prepared, opts));
    if let Err(e) = result {
        eprintln!("install failed — rolling back: {e}");
        rollback_install(&prepared, &backups);
        return Err(e);
    }
    Ok(())
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
    host: &HostBundle,
) -> Result<Option<PreparedInstall>> {
    let candidate = load_candidate(source, opts.max_size)?;
    let readiness = assess_candidate(&candidate, &registry, opts)?;
    let upgrading = match readiness {
        InstallReadiness::AlreadyCurrent => return Ok(None),
        InstallReadiness::Proceed { upgrading } => upgrading,
    };
    // Origin precedence: --origin > embedded in the package > URL-sibling guess.
    let origin = opts
        .origin
        .clone()
        .or_else(|| candidate.payload.embedded_origin.clone())
        .or_else(|| opts.derived_origin.clone());
    if let Some(o) = &origin {
        println!("update origin: {o}");
    }
    let next = registry_with_candidate(&registry, &candidate, origin.as_deref())?;
    if candidate.payload.from_package
        && next
            .get(&candidate.manifest.id)
            .and_then(|m| m.origin.as_ref())
            .is_none()
    {
        eprintln!("note: this package carries no update origin — `iimod update` will not cover it");
    }
    dry_run_stock_composition(host, &next)?;
    let module_dicts = translations::load_module_dicts(&candidate.payload.dir)?;
    let stock_targets = all_stock_targets(host, &next, &[]);
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
    let origin = origin.map(str::to_string).or_else(|| {
        next.get(&candidate.manifest.id)
            .and_then(|m| m.origin.clone())
    });
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

fn dry_run_stock_composition(host: &HostBundle, registry: &Registry) -> Result<()> {
    let ii = paths::ii_root();
    for rel in all_stock_targets(host, registry, &[]) {
        let target = ii.join(&rel);
        if target.exists() {
            let current = std::fs::read_to_string(&target)?;
            patch::recompose(&current, &full_patch_set(host, registry, &rel, None))?;
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
    backups.add("registry.json", &paths::registry_path())?;
    backups.add("index.json", &paths::index_projection_path())?;
    backups.add_tree("module", &prepared.module_dir)?;
    backups.add_tree(
        "store-version",
        &store::store_path(
            &prepared.candidate.manifest.id,
            &prepared.candidate.manifest.version,
        ),
    )?;
    for (label, path) in [
        (
            "host/ModuleHost.qml",
            paths::host_dir().join("ModuleHost.qml"),
        ),
        (
            "host/ModulesConfig.qml",
            paths::host_dir().join("ModulesConfig.qml"),
        ),
        (
            "host/ModuleImports.qml",
            paths::host_dir().join("ModuleImports.qml"),
        ),
        ("host/sentinel", paths::host_sentinel()),
        ("host/current.json", paths::host_current_path()),
    ] {
        backups.add(label, &path)?;
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

fn apply_install_mutation(prepared: &mut PreparedInstall, host: &HostBundle) -> Result<()> {
    stage_module_payload(prepared)?;
    refresh_pristine_snapshots(prepared)?;
    hostpatch::ensure_host(host, &|rel| prepared.next.patches_for_file(rel))?;
    recompose_all(host, &prepared.next, true)?;
    hostpatch::write_module_imports(&module_import_ids(&prepared.next))?;
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
    let _ = backups.restore("registry.json", &paths::registry_path());
    let _ = backups.restore("index.json", &paths::index_projection_path());
    let _ = backups.restore_tree("module", &prepared.module_dir);
    let _ = backups.restore_tree(
        "store-version",
        &store::store_path(
            &prepared.candidate.manifest.id,
            &prepared.candidate.manifest.version,
        ),
    );
    for (label, path) in [
        (
            "host/ModuleHost.qml",
            paths::host_dir().join("ModuleHost.qml"),
        ),
        (
            "host/ModulesConfig.qml",
            paths::host_dir().join("ModulesConfig.qml"),
        ),
        (
            "host/ModuleImports.qml",
            paths::host_dir().join("ModuleImports.qml"),
        ),
        ("host/sentinel", paths::host_sentinel()),
        ("host/current.json", paths::host_current_path()),
    ] {
        let _ = backups.restore(label, &path);
    }
    let _ = std::fs::remove_file(paths::journal_path());
}

fn commit_install(prepared: &mut PreparedInstall, opts: &InstallOpts) -> Result<()> {
    prepared.next.host_version = Some(hostpatch::HOST_VERSION.to_string());
    if opts.no_enable {
        let id = prepared.candidate.manifest.id.clone();
        prepared.next.get_mut(&id).unwrap().state = ModuleState::Disabled;
    }
    registry::save(&prepared.next)?;
    project_new_state(&prepared.next)?;
    store::prune_backups(BACKUPS_TO_KEEP)?;
    reload_and_reconcile(&prepared.next)?;
    print_install_result(prepared, opts);
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
