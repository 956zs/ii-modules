//! Authoritative state: ~/.local/share/iimp/registry.json (SPEC 1.0 §8.2).
//! Atomic writes (temp+rename, one .bak); single-writer lock; topological helpers.

use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::exit::{self, bail};
use crate::manifest::Manifest;
use crate::patch::PatchInstance;
use crate::paths;

// v2: adds InstalledModule.origin (update index URL). Missing on v1 records —
// serde default covers the forward migration; writes stamp the new version.
pub const REGISTRY_SCHEMA_VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ModuleState {
    Enabled,
    Disabled,
    Incompatible,
    BlockedByDep,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct InstalledModule {
    pub manifest: Manifest,
    pub state: ModuleState,
    /// relpath (within $II/mod/<id>/) → sha256 of the installed file
    pub files: BTreeMap<String, String>,
    /// Patches as applied (owner == manifest.id), targets are $II-relative
    pub patch_records: BTreeMap<String, Vec<PatchInstance>>,
    /// locale → keys this module owns in the merged translation dicts
    pub translation_keys: BTreeMap<String, Vec<String>>,
    pub installed_at_epoch: u64,
    /// Update index URL (`iimod install --origin`); consulted by `iimod update`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Registry {
    pub schema_version: u32,
    #[serde(default)]
    pub host_version: Option<String>,
    #[serde(default)]
    pub modules: Vec<InstalledModule>,
}

impl Default for Registry {
    fn default() -> Self {
        Registry {
            schema_version: REGISTRY_SCHEMA_VERSION,
            host_version: None,
            modules: Vec::new(),
        }
    }
}

impl Registry {
    pub fn get(&self, id: &str) -> Option<&InstalledModule> {
        self.modules.iter().find(|m| m.manifest.id == id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut InstalledModule> {
        self.modules.iter_mut().find(|m| m.manifest.id == id)
    }

    pub fn remove(&mut self, id: &str) -> Option<InstalledModule> {
        let pos = self.modules.iter().position(|m| m.manifest.id == id)?;
        Some(self.modules.remove(pos))
    }

    /// Direct dependents of `id` among installed modules.
    pub fn dependents_of(&self, id: &str) -> Vec<&InstalledModule> {
        self.modules
            .iter()
            .filter(|m| m.manifest.requires.modules.iter().any(|d| d.id == id))
            .collect()
    }

    /// Transitive dependent closure (excluding `id` itself), deterministic order.
    pub fn dependent_closure(&self, id: &str) -> Vec<String> {
        let mut result: Vec<String> = Vec::new();
        let mut frontier = vec![id.to_string()];
        while let Some(current) = frontier.pop() {
            for dep in self.dependents_of(&current) {
                let did = dep.manifest.id.clone();
                if did != id && !result.contains(&did) {
                    result.push(did.clone());
                    frontier.push(did);
                }
            }
        }
        result.sort();
        result
    }

    /// All installed modules in dependency-topological order (dependencies first),
    /// ties broken by id. Errors on cycles (defensive: registry hand-edits).
    pub fn topological_order(&self) -> Result<Vec<String>> {
        let ids: Vec<String> = self.modules.iter().map(|m| m.manifest.id.clone()).collect();
        let mut in_deg: BTreeMap<String, usize> = ids.iter().map(|i| (i.clone(), 0)).collect();
        for module in &self.modules {
            for dep in &module.manifest.requires.modules {
                if in_deg.contains_key(&dep.id) {
                    *in_deg.get_mut(&module.manifest.id).unwrap() += 1;
                }
            }
        }
        let mut order = Vec::new();
        while order.len() < ids.len() {
            let Some(next) = in_deg
                .iter()
                .filter(|(_, d)| **d == 0)
                .map(|(i, _)| i.clone())
                .find(|i| !order.contains(i))
            else {
                return Err(bail(exit::STATE, "dependency cycle detected in registry"));
            };
            *in_deg.get_mut(&next).unwrap() = usize::MAX; // consumed
            for module in &self.modules {
                if module
                    .manifest
                    .requires
                    .modules
                    .iter()
                    .any(|d| d.id == next)
                {
                    let d = in_deg.get_mut(&module.manifest.id).unwrap();
                    if *d != usize::MAX {
                        *d -= 1;
                    }
                }
            }
            order.push(next);
        }
        Ok(order)
    }

    /// Surviving patch set for one stock file across all non-incompatible modules.
    pub fn patches_for_file(&self, rel: &str) -> Vec<PatchInstance> {
        let mut set: Vec<PatchInstance> = self
            .modules
            .iter()
            .filter(|m| {
                !matches!(
                    m.state,
                    ModuleState::Incompatible | ModuleState::BlockedByDep
                )
            })
            .flat_map(|m| m.patch_records.get(rel).cloned().unwrap_or_default())
            .collect();
        set.sort_by_key(|p| (p.owner.clone(), p.index));
        set
    }

    /// Every stock file any installed module patches.
    pub fn all_patched_files(&self) -> Vec<String> {
        let mut files: Vec<String> = self
            .modules
            .iter()
            .flat_map(|m| m.patch_records.keys().cloned())
            .collect();
        files.sort();
        files.dedup();
        files
    }
}

pub fn load() -> Result<Registry> {
    load_from(&paths::registry_path())
}

pub fn load_from(path: &Path) -> Result<Registry> {
    if !path.exists() {
        return Ok(Registry::default());
    }
    let bytes = std::fs::read(path).with_context(|| format!("reading {}", path.display()))?;
    let registry: Registry = serde_json::from_slice(&bytes).map_err(|e| {
        bail(
            exit::STATE,
            format!("registry corrupt ({e}); run: iimod doctor --rebuild-registry"),
        )
    })?;
    if registry.schema_version > REGISTRY_SCHEMA_VERSION {
        return Err(bail(
            exit::PROTOCOL,
            format!(
                "registry schemaVersion {} was written by a newer iimod; upgrade iimod (this build supports {})",
                registry.schema_version, REGISTRY_SCHEMA_VERSION
            ),
        ));
    }
    Ok(registry)
}

pub fn save(registry: &Registry) -> Result<()> {
    save_to(&paths::registry_path(), registry)
}

pub fn save_to(path: &Path, registry: &Registry) -> Result<()> {
    let parent = path.parent().expect("registry path has a parent");
    std::fs::create_dir_all(parent)?;
    if path.exists() {
        let _ = std::fs::copy(path, path.with_extension("json.bak"));
    }
    let tmp = path.with_extension("json.tmp");
    let mut f = std::fs::File::create(&tmp)?;
    f.write_all(serde_json::to_string_pretty(registry)?.as_bytes())?;
    f.write_all(b"\n")?;
    f.sync_all()?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Single-writer lock. O_EXCL create with pid; stale (dead pid) locks are reclaimed.
#[derive(Debug)]
pub struct Lock {
    path: PathBuf,
}

impl Lock {
    pub fn acquire() -> Result<Lock> {
        Self::acquire_at(&paths::lock_path())
    }

    pub fn acquire_at(path: &Path) -> Result<Lock> {
        std::fs::create_dir_all(path.parent().expect("lock path has a parent"))?;
        for attempt in 0..2 {
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(path)
            {
                Ok(mut f) => {
                    let _ = writeln!(f, "{}", std::process::id());
                    return Ok(Lock {
                        path: path.to_path_buf(),
                    });
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt == 0 => {
                    let holder = std::fs::read_to_string(path).unwrap_or_default();
                    let pid: Option<u32> = holder.trim().parse().ok();
                    let alive = pid
                        .map(|p| Path::new(&format!("/proc/{p}")).exists())
                        .unwrap_or(false);
                    if alive {
                        return Err(bail(
                            exit::STATE,
                            format!(
                                "another iimod is running (pid {}); lock: {}",
                                holder.trim(),
                                path.display()
                            ),
                        ));
                    }
                    let _ = std::fs::remove_file(path); // stale — reclaim
                }
                Err(e) => return Err(bail(exit::STATE, format!("cannot acquire lock: {e}"))),
            }
        }
        Err(bail(
            exit::STATE,
            "cannot acquire lock after reclaiming a stale one",
        ))
    }
}

impl Drop for Lock {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

pub fn now_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest;

    fn tmp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("iimp-reg-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn module(id: &str, deps: &[&str]) -> InstalledModule {
        let mut m: Manifest = serde_json::from_str(include_str!(
            "../../../spec/fixtures/valid/tier-a-minimal.json"
        ))
        .unwrap();
        m.id = id.to_string();
        m.requires.modules = deps
            .iter()
            .map(|d| manifest::ModuleReq {
                id: d.to_string(),
                version_req: "*".into(),
            })
            .collect();
        InstalledModule {
            manifest: m,
            state: ModuleState::Enabled,
            files: BTreeMap::new(),
            patch_records: BTreeMap::new(),
            translation_keys: BTreeMap::new(),
            installed_at_epoch: 0,
            origin: None,
        }
    }

    #[test]
    fn roundtrip_and_bak() {
        let dir = tmp("roundtrip");
        let path = dir.join("registry.json");
        let mut reg = Registry::default();
        reg.modules.push(module("aaa", &[]));
        save_to(&path, &reg).unwrap();
        save_to(&path, &reg).unwrap(); // second save creates .bak
        assert!(path.with_extension("json.bak").exists());
        let loaded = load_from(&path).unwrap();
        assert_eq!(loaded.modules.len(), 1);
    }

    #[test]
    fn corrupt_registry_is_state_error() {
        let dir = tmp("corrupt");
        let path = dir.join("registry.json");
        std::fs::write(&path, b"{not json").unwrap();
        let err = load_from(&path).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::STATE);
    }

    #[test]
    fn newer_schema_refused() {
        let dir = tmp("newer");
        let path = dir.join("registry.json");
        std::fs::write(
            &path,
            br#"{"schemaVersion": 99, "hostVersion": null, "modules": []}"#,
        )
        .unwrap();
        let err = load_from(&path).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROTOCOL);
    }

    #[test]
    fn topo_and_closures() {
        let mut reg = Registry::default();
        reg.modules.push(module("app", &["lib"]));
        reg.modules.push(module("lib", &[]));
        reg.modules.push(module("plugin", &["app"]));
        let order = reg.topological_order().unwrap();
        let pos = |id: &str| order.iter().position(|x| x == id).unwrap();
        assert!(pos("lib") < pos("app"));
        assert!(pos("app") < pos("plugin"));
        assert_eq!(
            reg.dependent_closure("lib"),
            vec!["app".to_string(), "plugin".to_string()]
        );
    }

    #[test]
    fn cycle_detected() {
        let mut reg = Registry::default();
        reg.modules.push(module("aaa", &["bbb"]));
        reg.modules.push(module("bbb", &["aaa"]));
        let err = reg.topological_order().unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::STATE);
    }

    #[test]
    fn lock_excludes_and_reclaims_stale() {
        let dir = tmp("lock");
        let path = dir.join("lock");
        let lock = Lock::acquire_at(&path).unwrap();
        let err = Lock::acquire_at(&path).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::STATE);
        drop(lock);
        // Stale lock with a dead pid is reclaimed.
        std::fs::write(&path, "999999999\n").unwrap();
        let _lock = Lock::acquire_at(&path).unwrap();
    }
}
