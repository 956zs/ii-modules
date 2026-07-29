//! iimod subcommands that have not yet been split into dedicated modules.

use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::hoststate::{self, MutationMode};
use crate::lint;
use crate::manifest::{self, Manifest};
use crate::ops::{
    all_stock_targets, check_deps_conflicts, full_patch_set, load_payload, module_import_ids,
    project_enabled, recompose_all, validate_payload, wipe_banner, write_index_projection,
};
use crate::patch::{self, PatchInstance};
use crate::paths;
use crate::pkg;
use crate::probe;
use crate::qs;
use crate::registry::{self, ModuleState};
use crate::store::{self, BackupSet};
use crate::translations;

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
    let host = hoststate::selected_or_candidate()?;
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
        let mut set = full_patch_set(&host, &registry, &p.file, Some(&m.id));
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
// uninstall / enable / disable
// ---------------------------------------------------------------------------

pub fn cmd_uninstall(id: &str, cascade: bool) -> Result<()> {
    let mutation = hoststate::mutation_preflight(MutationMode::Normal)?;
    let mut registry = registry::load()?;
    reject_wiped_tree(&registry)?;
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
    let previous_registry = registry.clone();
    let previous_dicts = translations::load_registry_dicts(&previous_registry)?;
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
    translations::validate_live_locales(translation_locales.iter().cloned())?;
    let stock_targets = all_stock_targets(mutation.host(), &previous_registry, &[]);
    let backups = begin_uninstall_backup(&victims, &translation_locales, &stock_targets)?;
    println!("removing: {victims:?}");

    let result = (|| {
        for victim in &victims {
            registry.remove(victim).expect("present");
            let dir = paths::mod_root().join(victim);
            if dir.exists() {
                std::fs::remove_dir_all(&dir)?;
            }
            store::remove_from_store(victim)?;
        }
        let mut warnings = Vec::new();
        translations::reconcile(
            &previous_registry,
            &previous_dicts,
            &mut registry,
            &translations::RegistryDicts::new(),
            &mut warnings,
        )?;
        for warning in warnings {
            eprintln!("warning: {warning}");
        }
        hostpatch::ensure_host(mutation.host(), &|rel| registry.patches_for_file(rel))?;
        recompose_all(mutation.host(), &registry, true)?;
        if paths::host_dir().exists() {
            hostpatch::write_module_imports(&module_import_ids(&registry))?;
        }
        mutation.activate_after_host_write()?;
        registry::save(&registry)?;
        write_index_projection(&registry)?;
        project_enabled(&registry)?;
        Ok(())
    })();
    if let Err(error) = result {
        eprintln!("uninstall failed — rolling back: {error}");
        rollback_uninstall(&backups, &victims, &translation_locales, &stock_targets);
        return Err(error);
    }

    store::prune_backups(10)?;
    let _ = qs::trigger_reload();
    println!("✓ uninstalled");
    Ok(())
}

fn begin_uninstall_backup(
    victims: &[String],
    translation_locales: &[String],
    stock_targets: &[String],
) -> Result<BackupSet> {
    let backups = BackupSet::create()?;
    let ii = paths::ii_root();
    for rel in stock_targets {
        backups.add(&format!("stock/{rel}"), &ii.join(rel))?;
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
    for victim in victims {
        backups.add_tree(
            &format!("modules/{victim}"),
            &paths::mod_root().join(victim),
        )?;
        backups.add_tree(&format!("store/{victim}"), &paths::store_dir().join(victim))?;
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
    Ok(backups)
}

fn rollback_uninstall(
    backups: &BackupSet,
    victims: &[String],
    translation_locales: &[String],
    stock_targets: &[String],
) {
    let ii = paths::ii_root();
    for rel in stock_targets {
        let _ = backups.restore(&format!("stock/{rel}"), &ii.join(rel));
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
    for victim in victims {
        let _ = backups.restore_tree(
            &format!("modules/{victim}"),
            &paths::mod_root().join(victim),
        );
        let _ = backups.restore_tree(&format!("store/{victim}"), &paths::store_dir().join(victim));
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
}

pub fn cmd_set_state(id: &str, enable: bool) -> Result<()> {
    let mutation = hoststate::mutation_preflight(MutationMode::Normal)?;
    let mut registry = registry::load()?;
    reject_wiped_tree(&registry)?;
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
    // Tier B state changes move patches in or out of the composition; Tier A
    // flips are config-list-only and reload live without this. Recompose
    // BEFORE persisting the registry: recomposition is the step that can fail
    // (anchors, permissions), and failing after the save would strand a
    // "disabled but still patched" inconsistency. recompose_all dry-runs
    // every target before writing any, so a failure here leaves the stock
    // tree untouched too.
    let tier_b_flip = to_flip
        .iter()
        .any(|t| registry.get(t).is_some_and(|m| m.manifest.is_tier_b()));
    if tier_b_flip {
        crate::ops::recompose_all(mutation.host(), &registry, true)?;
    }
    hostpatch::ensure_host(mutation.host(), &|rel| registry.patches_for_file(rel))?;
    hostpatch::write_module_imports(&module_import_ids(&registry))?;
    mutation.activate_after_host_write()?;
    registry::save(&registry)?;
    write_index_projection(&registry)?;
    project_enabled(&registry)?;
    if tier_b_flip {
        let _ = crate::qs::trigger_reload();
    }
    println!(
        "✓ {} {:?}",
        if enable { "enabled" } else { "disabled" },
        to_flip
    );
    Ok(())
}

fn reject_wiped_tree(registry: &crate::registry::Registry) -> Result<()> {
    if !wipe_banner(registry) {
        return Ok(());
    }
    Err(bail(
        exit::STATE,
        "shell tree is wiped; run `iimod reapply` before mutating modules",
    ))
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

pub fn cmd_pack(
    payload: &Path,
    out: Option<PathBuf>,
    origin: Option<&str>,
    no_origin: bool,
) -> Result<()> {
    if origin.is_none() && !no_origin {
        return Err(bail(
            exit::USAGE,
            "packages must carry their update origin: pass --origin <update-index-url> so installers get `iimod update` for free, or --no-origin to explicitly opt out for local/dev packaging",
        ));
    }
    let (m, warnings) = validate_payload(payload)?;
    for w in warnings {
        eprintln!("warning: {w}");
    }
    let out = out.unwrap_or_else(|| PathBuf::from(format!("{}-{}.iimod", m.id, m.version)));
    pkg::pack(payload, &m.id, &out, origin)?;
    println!(
        "✓ packed {} v{} → {}{}",
        m.id,
        m.version,
        out.display(),
        origin
            .map(|o| format!("  (origin: {o})"))
            .unwrap_or_default()
    );
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
