//! Recovery commands: repair installed files and reapply after shell updates.

use std::path::Path;

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::hoststate::{self, HostBundle, MutationMode};
use crate::ops::{
    all_stock_targets, module_import_ids, project_enabled, recompose_all, write_index_projection,
};
use crate::patch;
use crate::paths;
use crate::probe;
use crate::qs;
use crate::registry::{self, ModuleState, Registry};
use crate::store::{self, BackupSet};
use crate::translations;

type ReapplyIssues = Vec<(String, String)>;

struct ReapplyIssue {
    id: String,
    reason: String,
    state: ModuleState,
}

pub fn cmd_repair(id: Option<&str>) -> Result<()> {
    let mutation = hoststate::mutation_preflight(MutationMode::Normal)?;
    let registry = registry::load()?;
    restore_one_module(id, &registry)?;
    hostpatch::ensure_host(mutation.host(), &|rel| registry.patches_for_file(rel))?;
    hostpatch::write_module_imports(&module_import_ids(&registry))?;
    recompose_all(mutation.host(), &registry, true)?;
    mutation.activate_after_host_write()?;
    write_index_projection(&registry)?;
    let _ = qs::trigger_reload();
    println!("✓ repaired");
    Ok(())
}

pub fn cmd_reapply() -> Result<()> {
    let backups = BackupSet::create()?;
    backups.add_tree("host-state", &paths::host_state_dir())?;
    let mutation = match hoststate::mutation_preflight(MutationMode::Reapply) {
        Ok(mutation) => mutation,
        Err(error) => {
            rollback_reapply_host_state(&backups);
            return Err(error);
        }
    };
    let mut registry = match registry::load() {
        Ok(registry) => registry,
        Err(error) => {
            rollback_reapply_host_state(&backups);
            return Err(error);
        }
    };
    let previous_registry = registry.clone();
    let previous_dicts = match translations::load_registry_dicts(&previous_registry) {
        Ok(dicts) => dicts,
        Err(error) => {
            rollback_reapply_host_state(&backups);
            return Err(error);
        }
    };
    if let Err(error) = translations::validate_live_locales(
        previous_registry
            .modules
            .iter()
            .flat_map(|module| module.translation_keys.keys().cloned())
            .chain(
                previous_dicts
                    .values()
                    .flat_map(|dicts| dicts.keys().cloned()),
            ),
    ) {
        rollback_reapply_host_state(&backups);
        return Err(error);
    }

    let ii = paths::ii_root();
    let order = match registry.topological_order() {
        Ok(order) => order,
        Err(error) => {
            rollback_reapply_host_state(&backups);
            return Err(error);
        }
    };
    let stock_targets = all_stock_targets(mutation.host(), &registry, &[]);
    let module_ids: Vec<String> = registry
        .modules
        .iter()
        .map(|module| module.manifest.id.clone())
        .collect();
    let translation_locales: Vec<String> = previous_registry
        .modules
        .iter()
        .flat_map(|module| module.translation_keys.keys().cloned())
        .chain(
            previous_dicts
                .values()
                .flat_map(|dicts| dicts.keys().cloned()),
        )
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect();
    if let Err(error) =
        begin_reapply_journal(&backups, &module_ids, &translation_locales, &stock_targets)
    {
        rollback_reapply_host_state(&backups);
        let _ = std::fs::remove_file(paths::journal_path());
        return Err(error);
    }
    let result = (|| {
        if registry.modules.is_empty() {
            reapply_empty_registry(&registry, &mutation)?;
            return Ok(Vec::new());
        }
        let mut issues = probe_modules(&mut registry, &order, &ii);
        refresh_pristine_snapshots(mutation.host(), &registry, &ii)?;
        restore_surviving_payloads(&mut registry, &order, &mut issues)?;
        recompose_surviving_patches(mutation.host(), &mut registry, &mut issues)?;
        recompose_all(mutation.host(), &registry, true)?;
        remerge_translations(&previous_registry, &previous_dicts, &mut registry)?;
        commit_reapply(&mut registry, &mutation)?;
        Ok(issues)
    })();
    let issues = match result {
        Ok(issues) => issues,
        Err(error) => {
            eprintln!("reapply failed — rolling back: {error}");
            rollback_reapply(&backups, &module_ids, &translation_locales, &stock_targets);
            return Err(error);
        }
    };
    let _ = std::fs::remove_file(paths::journal_path());
    store::prune_backups(10)?;
    if !registry.modules.is_empty() {
        print_reapply_result(&issues);
    }
    Ok(())
}

fn begin_reapply_journal(
    backups: &BackupSet,
    module_ids: &[String],
    translation_locales: &[String],
    stock_targets: &[String],
) -> Result<()> {
    let ii = paths::ii_root();
    for rel in stock_targets {
        backups.add(&format!("stock/{rel}"), &ii.join(rel))?;
        backups.add(&format!("pristine/{rel}"), &paths::pristine_dir().join(rel))?;
    }
    backups.add("registry.json", &paths::registry_path())?;
    backups.add("index.json", &paths::index_projection_path())?;
    backups.add(
        "config.json",
        &paths::shell_config_root().join("config.json"),
    )?;
    for locale in translation_locales {
        backups.add(
            &format!("translations/{locale}.json"),
            &paths::translations_dir().join(format!("{locale}.json")),
        )?;
    }
    for id in module_ids {
        backups.add_tree(&format!("modules/{id}"), &paths::mod_root().join(id))?;
        backups.add_tree(&format!("store/{id}"), &paths::store_dir().join(id))?;
    }
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
    std::fs::write(
        paths::journal_path(),
        serde_json::to_string_pretty(&serde_json::json!({
            "op": "reapply",
            "backups": &backups.dir,
            "stockTargets": stock_targets,
            "moduleIds": module_ids,
            "translationLocales": translation_locales,
        }))? + "\n",
    )?;
    Ok(())
}

fn rollback_reapply_host_state(backups: &BackupSet) {
    let _ = backups.restore_tree("host-state", &paths::host_state_dir());
}

fn rollback_reapply(
    backups: &BackupSet,
    module_ids: &[String],
    translation_locales: &[String],
    stock_targets: &[String],
) {
    let ii = paths::ii_root();
    for rel in stock_targets {
        let _ = backups.restore(&format!("stock/{rel}"), &ii.join(rel));
        let _ = backups.restore(&format!("pristine/{rel}"), &paths::pristine_dir().join(rel));
    }
    let _ = backups.restore("registry.json", &paths::registry_path());
    let _ = backups.restore("index.json", &paths::index_projection_path());
    let _ = backups.restore(
        "config.json",
        &paths::shell_config_root().join("config.json"),
    );
    for locale in translation_locales {
        let _ = backups.restore(
            &format!("translations/{locale}.json"),
            &paths::translations_dir().join(format!("{locale}.json")),
        );
    }
    for id in module_ids {
        let _ = backups.restore_tree(&format!("modules/{id}"), &paths::mod_root().join(id));
        let _ = backups.restore_tree(&format!("store/{id}"), &paths::store_dir().join(id));
    }
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
    let _ = backups.restore_tree("host-state", &paths::host_state_dir());
    let _ = std::fs::remove_file(paths::journal_path());
}

fn restore_one_module(id: Option<&str>, registry: &Registry) -> Result<()> {
    let Some(id) = id else {
        return Ok(());
    };
    let Some(module) = registry.get(id) else {
        return Err(bail(exit::USAGE, format!("module {id:?} is not installed")));
    };
    let src = store::store_path(id, &module.manifest.version);
    let dest = paths::mod_root().join(id);
    if dest.exists() {
        std::fs::remove_dir_all(&dest)?;
    }
    store::copy_tree(&src, &dest)?;
    Ok(())
}

fn reapply_empty_registry(
    registry: &Registry,
    mutation: &hoststate::MutationContext,
) -> Result<()> {
    println!("no modules installed; ensuring host only if previously present");
    if registry.host_version.is_some() || paths::host_dir().exists() {
        hostpatch::ensure_host(mutation.host(), &|_| Vec::new())?;
        mutation.activate_after_host_write()?;
    }
    Ok(())
}

fn probe_modules(registry: &mut Registry, order: &[String], ii: &Path) -> ReapplyIssues {
    let mut issues = Vec::new();
    for id in order {
        let module = registry.get(id).unwrap();
        let failures = probe::evaluate(ii, &module.manifest.compat.probes);
        if !failures.is_empty() {
            record_issue(
                registry,
                &mut issues,
                ReapplyIssue::incompatible(id, probe_reason(&failures)),
            );
            continue;
        }
        if dependency_already_failed(module, &issues) {
            record_issue(
                registry,
                &mut issues,
                ReapplyIssue::blocked(id, "blocked by incompatible dependency"),
            );
            continue;
        }
        reset_recovered_module(registry, id);
    }
    issues
}

fn dependency_already_failed(
    module: &crate::registry::InstalledModule,
    issues: &ReapplyIssues,
) -> bool {
    module
        .manifest
        .requires
        .modules
        .iter()
        .any(|d| issues.iter().any(|(bad, _)| bad == &d.id))
}

impl ReapplyIssue {
    fn incompatible(id: &str, reason: String) -> Self {
        Self {
            id: id.to_string(),
            reason,
            state: ModuleState::Incompatible,
        }
    }

    fn blocked(id: &str, reason: &str) -> Self {
        Self {
            id: id.to_string(),
            reason: reason.to_string(),
            state: ModuleState::BlockedByDep,
        }
    }
}

fn record_issue(registry: &mut Registry, issues: &mut ReapplyIssues, issue: ReapplyIssue) {
    registry.get_mut(&issue.id).unwrap().state = issue.state;
    issues.push((issue.id, issue.reason));
}

fn probe_reason(failures: &[probe::ProbeFailure]) -> String {
    failures
        .iter()
        .map(|f| format!("{} ({})", f.probe.path, f.probe.reason))
        .collect::<Vec<_>>()
        .join("; ")
}

fn reset_recovered_module(registry: &mut Registry, id: &str) {
    if matches!(
        registry.get(id).unwrap().state,
        ModuleState::Incompatible | ModuleState::BlockedByDep
    ) {
        // Previously incompatible, now probing clean: user opts back in explicitly.
        registry.get_mut(id).unwrap().state = ModuleState::Disabled;
    }
}

fn refresh_pristine_snapshots(host: &HostBundle, registry: &Registry, ii: &Path) -> Result<()> {
    for rel in all_stock_targets(host, registry, &[]) {
        let target = ii.join(&rel);
        if target.exists() {
            let current = std::fs::read_to_string(&target)?;
            if let Ok((stripped, _)) = patch::strip(&current) {
                store::refresh_pristine_snapshot(&rel, &stripped)?;
            }
        }
    }
    Ok(())
}

fn restore_surviving_payloads(
    registry: &mut Registry,
    order: &[String],
    issues: &mut ReapplyIssues,
) -> Result<()> {
    for id in order {
        let module = registry.get(id).unwrap();
        if is_incompatible(module.state) {
            continue;
        }
        let src = store::store_path(id, &module.manifest.version);
        if !src.exists() {
            record_issue(
                registry,
                issues,
                ReapplyIssue::incompatible(id, "store payload missing".into()),
            );
            continue;
        }
        replace_module_dir(id, &src)?;
    }
    Ok(())
}

fn is_incompatible(state: ModuleState) -> bool {
    matches!(state, ModuleState::Incompatible | ModuleState::BlockedByDep)
}

fn replace_module_dir(id: &str, src: &Path) -> Result<()> {
    let dest = paths::mod_root().join(id);
    if dest.exists() {
        std::fs::remove_dir_all(&dest)?;
    }
    store::copy_tree(src, &dest)?;
    Ok(())
}

fn recompose_surviving_patches(
    host: &HostBundle,
    registry: &mut Registry,
    issues: &mut ReapplyIssues,
) -> Result<()> {
    for _attempt in 0..2 {
        match hostpatch::ensure_host(host, &|rel| registry.patches_for_file(rel)) {
            Ok(_) => return Ok(()),
            Err(e) if exit::code_of(&e) == exit::ANCHOR => {
                let msg = format!("{e}");
                let Some(id) = anchor_owner(registry, &msg) else {
                    return Err(e);
                };
                record_issue(
                    registry,
                    issues,
                    ReapplyIssue::incompatible(&id, format!("anchor failure: {msg}")),
                );
            }
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

fn anchor_owner(registry: &Registry, msg: &str) -> Option<String> {
    registry
        .modules
        .iter()
        .map(|m| m.manifest.id.clone())
        .find(|id| msg.contains(&format!("{id}/")))
}

fn remerge_translations(
    previous: &Registry,
    previous_dicts: &translations::RegistryDicts,
    registry: &mut Registry,
) -> Result<()> {
    let mut warnings = Vec::new();
    translations::reconcile(
        previous,
        previous_dicts,
        registry,
        &translations::RegistryDicts::new(),
        &mut warnings,
    )?;
    for warning in warnings {
        eprintln!("warning: {warning}");
    }
    Ok(())
}

fn commit_reapply(registry: &mut Registry, mutation: &hoststate::MutationContext) -> Result<()> {
    hostpatch::write_module_imports(&module_import_ids(registry))?;
    mutation.activate_after_host_write()?;
    registry.host_version = Some(hostpatch::HOST_VERSION.to_string());
    registry::save(registry)?;
    write_index_projection(registry)?;
    project_enabled(registry)?;
    let _ = qs::trigger_reload();
    Ok(())
}

fn print_reapply_result(issues: &ReapplyIssues) {
    if issues.is_empty() {
        println!("✓ reapplied all modules");
        return;
    }
    println!(
        "reapplied with {} module(s) disabled as incompatible:",
        issues.len()
    );
    for (id, reason) in issues {
        println!("  ✗ {id}: {reason}");
    }
    println!("they stay disabled until updated versions pass their probes");
}
