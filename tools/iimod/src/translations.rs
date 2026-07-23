//! Translation dict merge/unmerge with per-key ownership (SPEC 1.0 §8.3).

use std::collections::BTreeMap;
use std::path::Path;

use anyhow::Result;

use crate::paths;
use crate::registry::Registry;

fn read_dict(path: &Path) -> BTreeMap<String, String> {
    std::fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
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

/// Is `key` in `locale` owned by another installed module?
fn owned_by_other(registry: &Registry, module_id: &str, locale: &str, key: &str) -> bool {
    registry.modules.iter().any(|m| {
        m.manifest.id != module_id
            && m.translation_keys
                .get(locale)
                .is_some_and(|keys| keys.iter().any(|k| k == key))
    })
}

/// Merge a module's dicts into the user's generated translation files.
/// Returns locale → keys now owned by this module; emits warnings for skips.
pub fn merge(
    registry: &Registry,
    module_id: &str,
    module_dicts: &BTreeMap<String, BTreeMap<String, String>>,
    warnings: &mut Vec<String>,
) -> Result<BTreeMap<String, Vec<String>>> {
    let mut owned: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for (locale, dict) in module_dicts {
        let path = paths::translations_dir().join(format!("{locale}.json"));
        let mut merged = read_dict(&path);
        let mut keys_owned = Vec::new();
        for (key, value) in dict {
            if owned_by_other(registry, module_id, locale, key) {
                if merged.get(key) != Some(value) {
                    warnings.push(format!(
                        "translation {locale}:{key:?} already owned by another module — skipped"
                    ));
                }
                continue;
            }
            if let Some(existing) = merged.get(key) {
                if existing != value && !owned.get(locale).is_some_and(|k| k.contains(key)) {
                    // Present but unowned → user's own entry; never overwrite.
                    warnings.push(format!(
                        "translation {locale}:{key:?} exists (user entry) — left untouched"
                    ));
                    continue;
                }
            }
            merged.insert(key.clone(), value.clone());
            keys_owned.push(key.clone());
        }
        if !keys_owned.is_empty() {
            write_dict(&path, &merged)?;
            owned.insert(locale.clone(), keys_owned);
        }
    }
    Ok(owned)
}

/// Remove keys the module owns, but only where the current value is still the
/// module's value (a user edit survives the uninstall).
pub fn unmerge(
    module_dicts: &BTreeMap<String, BTreeMap<String, String>>,
    owned: &BTreeMap<String, Vec<String>>,
) -> Result<()> {
    for (locale, keys) in owned {
        let path = paths::translations_dir().join(format!("{locale}.json"));
        let mut dict = read_dict(&path);
        let module_dict = module_dicts.get(locale);
        let mut changed = false;
        for key in keys {
            let module_value = module_dict.and_then(|d| d.get(key));
            if dict.get(key).map(String::as_str) == module_value.map(String::as_str) {
                dict.remove(key);
                changed = true;
            }
        }
        if changed {
            write_dict(&path, &dict)?;
        }
    }
    Ok(())
}

/// Load `translations/<locale>.json` dicts from a payload dir.
pub fn load_module_dicts(payload: &Path) -> Result<BTreeMap<String, BTreeMap<String, String>>> {
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
