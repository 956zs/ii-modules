//! Translation dictionary reconciliation with registry-backed references (SPEC 1.0 §8.3).

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use anyhow::Result;

use crate::exit;
use crate::paths;
use crate::registry::Registry;
use crate::store;

pub type ModuleDicts = BTreeMap<String, BTreeMap<String, String>>;
pub type RegistryDicts = BTreeMap<String, ModuleDicts>;

fn read_live_dict(path: &Path) -> Result<BTreeMap<String, String>> {
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(BTreeMap::new()),
        Err(error) => {
            return Err(exit::bail(
                exit::INTEGRITY,
                format!(
                    "generated translation dictionary {} is unreadable: {error}",
                    path.display()
                ),
            ))
        }
    };
    serde_json::from_slice(&bytes).map_err(|error| {
        exit::bail(
            exit::INTEGRITY,
            format!(
                "generated translation dictionary {} is invalid: {error}",
                path.display()
            ),
        )
    })
}

fn write_dict(path: &Path, dict: &BTreeMap<String, String>) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_string_pretty(dict)? + "\n")?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Load translation dictionaries for every installed module from immutable store payloads.
pub fn load_registry_dicts(registry: &Registry) -> Result<RegistryDicts> {
    let mut dicts = BTreeMap::new();
    for module in &registry.modules {
        let payload = store::store_path(&module.manifest.id, &module.manifest.version);
        let module_dicts = load_module_dicts(&payload).map_err(|error| {
            exit::bail(
                exit::INTEGRITY,
                format!(
                    "store translation dictionaries for module {:?} are invalid: {error}",
                    module.manifest.id
                ),
            )
        })?;
        for (locale, keys) in &module.translation_keys {
            let missing: Vec<&str> = keys
                .iter()
                .filter(|key| {
                    !module_dicts
                        .get(locale)
                        .is_some_and(|dict| dict.contains_key(key.as_str()))
                })
                .map(String::as_str)
                .collect();
            if !missing.is_empty() {
                return Err(exit::bail(
                    exit::INTEGRITY,
                    format!(
                        "store translation dictionary for module {:?} locale {locale} is missing managed keys {missing:?}",
                        module.manifest.id
                    ),
                ));
            }
        }
        dicts.insert(module.manifest.id.clone(), module_dicts);
    }
    Ok(dicts)
}

pub fn validate_live_locales(locales: impl IntoIterator<Item = String>) -> Result<()> {
    for locale in locales {
        read_live_dict(&paths::translations_dir().join(format!("{locale}.json")))?;
    }
    Ok(())
}

/// Return every locale that an install reconciliation can touch.
pub fn reconciliation_locales(
    previous_registry: &Registry,
    previous: &RegistryDicts,
    candidate: &ModuleDicts,
) -> BTreeSet<String> {
    previous_registry
        .modules
        .iter()
        .flat_map(|module| module.translation_keys.keys().cloned())
        .chain(previous.values().flat_map(|dicts| dicts.keys().cloned()))
        .chain(candidate.keys().cloned())
        .collect()
}

/// Reconcile generated dictionaries against all target registry contributors.
///
/// `previous_dicts` must be captured before an install replaces a store payload.
/// `overrides` supplies install candidates that are not yet authoritative in the store.
/// Every target module's `translationKeys` is reconstructed as references to values
/// currently projected into the generated dictionaries.
pub fn reconcile(
    previous: &Registry,
    previous_dicts: &RegistryDicts,
    target: &mut Registry,
    overrides: &RegistryDicts,
    warnings: &mut Vec<String>,
) -> Result<()> {
    let target_dicts = target_registry_dicts(target, overrides)?;
    let mut locales = BTreeSet::new();
    let mut keys_by_locale: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();

    for module in &previous.modules {
        for (locale, keys) in &module.translation_keys {
            locales.insert(locale.clone());
            keys_by_locale
                .entry(locale.clone())
                .or_default()
                .extend(keys.iter().cloned());
        }
    }
    for dicts in target_dicts.values() {
        for (locale, dict) in dicts {
            locales.insert(locale.clone());
            keys_by_locale
                .entry(locale.clone())
                .or_default()
                .extend(dict.keys().cloned());
        }
    }

    for module in &mut target.modules {
        module.translation_keys.clear();
    }

    for locale in locales {
        let path = paths::translations_dir().join(format!("{locale}.json"));
        let mut output = read_live_dict(&path)?;
        let mut changed = false;
        for key in keys_by_locale.remove(&locale).unwrap_or_default() {
            let contributors = contributors_for(target, &target_dicts, &locale, &key);
            let managed_values = previous_managed_values(previous, previous_dicts, &locale, &key);
            let current = output.get(&key).cloned();

            let selected = match current.as_ref() {
                Some(value) if contributors.iter().any(|c| c.value == *value) => {
                    Some(value.clone())
                }
                None if !contributors.is_empty() => Some(contributors[0].value.clone()),
                Some(value) if managed_values.contains(value) && !contributors.is_empty() => {
                    Some(contributors[0].value.clone())
                }
                Some(value) if managed_values.contains(value) => {
                    output.remove(&key);
                    changed = true;
                    None
                }
                _ => None,
            };

            let Some(selected) = selected else {
                continue;
            };
            if output.get(&key) != Some(&selected) {
                output.insert(key.clone(), selected.clone());
                changed = true;
            }

            let distinct_values: BTreeSet<&str> =
                contributors.iter().map(|c| c.value.as_str()).collect();
            if distinct_values.len() > 1 {
                warnings.push(format!(
                    "translation {locale}:{key:?} has conflicting contributors; kept deterministic value {selected:?}"
                ));
            }
            for contributor in contributors.iter().filter(|c| c.value == selected) {
                target
                    .get_mut(&contributor.module_id)
                    .expect("contributor is installed")
                    .translation_keys
                    .entry(locale.clone())
                    .or_default()
                    .push(key.clone());
            }
        }
        if changed {
            write_dict(&path, &output)?;
        }
    }
    Ok(())
}

fn target_registry_dicts(target: &Registry, overrides: &RegistryDicts) -> Result<RegistryDicts> {
    let mut dicts = BTreeMap::new();
    for module in &target.modules {
        let id = &module.manifest.id;
        let module_dicts = match overrides.get(id) {
            Some(override_dicts) => override_dicts.clone(),
            None => {
                let payload = store::store_path(id, &module.manifest.version);
                load_module_dicts(&payload)?
            }
        };
        dicts.insert(id.clone(), module_dicts);
    }
    Ok(dicts)
}

struct Contributor {
    module_id: String,
    value: String,
    installed_at_epoch: u64,
}

fn contributors_for(
    registry: &Registry,
    dicts: &RegistryDicts,
    locale: &str,
    key: &str,
) -> Vec<Contributor> {
    let mut contributors: Vec<Contributor> = registry
        .modules
        .iter()
        .filter_map(|module| {
            let value = dicts
                .get(&module.manifest.id)?
                .get(locale)?
                .get(key)?
                .clone();
            Some(Contributor {
                module_id: module.manifest.id.clone(),
                value,
                installed_at_epoch: module.installed_at_epoch,
            })
        })
        .collect();
    contributors.sort_by_key(|c| (c.installed_at_epoch, c.module_id.clone()));
    contributors
}

fn previous_managed_values(
    registry: &Registry,
    dicts: &RegistryDicts,
    locale: &str,
    key: &str,
) -> BTreeSet<String> {
    registry
        .modules
        .iter()
        .filter(|module| {
            module
                .translation_keys
                .get(locale)
                .is_some_and(|keys| keys.iter().any(|managed| managed == key))
        })
        .filter_map(|module| {
            dicts
                .get(&module.manifest.id)?
                .get(locale)?
                .get(key)
                .cloned()
        })
        .collect()
}

/// Load `translations/<locale>.json` dicts from a payload dir.
pub fn load_module_dicts(payload: &Path) -> Result<ModuleDicts> {
    let mut dicts = BTreeMap::new();
    let dir = payload.join("translations");
    if dir.is_dir() {
        for entry in std::fs::read_dir(&dir)?.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some(locale) = name.strip_suffix(".json") {
                if crate::manifest::is_valid_locale(locale) {
                    let dict: BTreeMap<String, String> =
                        serde_json::from_slice(&std::fs::read(entry.path())?).map_err(|e| {
                            crate::exit::bail(
                                crate::exit::VALIDATION,
                                format!("translations/{name}: {e}"),
                            )
                        })?;
                    dicts.insert(locale.to_string(), dict);
                } else {
                    return Err(crate::exit::bail(
                        crate::exit::VALIDATION,
                        format!("translations/{name}: invalid locale filename"),
                    ));
                }
            }
        }
    }
    Ok(dicts)
}
