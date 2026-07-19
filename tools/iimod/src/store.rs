//! Store / pristine / backups management (SPEC 1.0 §8.2) + hashing helpers.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::paths;

pub fn sha256_bytes(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

pub fn sha256_file(path: &Path) -> Result<String> {
    let bytes = std::fs::read(path).with_context(|| format!("hashing {}", path.display()))?;
    Ok(sha256_bytes(&bytes))
}

/// relpath → sha256 for every regular file under `root`.
pub fn hash_tree(root: &Path) -> Result<BTreeMap<String, String>> {
    let mut map = BTreeMap::new();
    for entry in WalkDir::new(root).sort_by_file_name() {
        let entry = entry?;
        if entry.file_type().is_file() {
            let rel = entry.path().strip_prefix(root).unwrap().to_string_lossy().into_owned();
            map.insert(rel, sha256_file(entry.path())?);
        }
    }
    Ok(map)
}

/// Copy a plain file tree (no symlinks — caller has already validated).
pub fn copy_tree(src: &Path, dest: &Path) -> Result<()> {
    for entry in WalkDir::new(src).sort_by_file_name() {
        let entry = entry?;
        let rel = entry.path().strip_prefix(src).unwrap();
        let target = dest.join(rel);
        if entry.file_type().is_dir() {
            std::fs::create_dir_all(&target)?;
        } else if entry.file_type().is_file() {
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(entry.path(), &target)
                .with_context(|| format!("copy {} -> {}", entry.path().display(), target.display()))?;
        }
    }
    Ok(())
}

pub fn store_path(id: &str, version: &str) -> PathBuf {
    paths::store_dir().join(id).join(version)
}

/// Put a payload into the store (replacing any same-version entry).
pub fn store_payload(id: &str, version: &str, payload: &Path) -> Result<PathBuf> {
    let dest = store_path(id, version);
    if dest.exists() {
        std::fs::remove_dir_all(&dest)?;
    }
    std::fs::create_dir_all(&dest)?;
    copy_tree(payload, &dest)?;
    Ok(dest)
}

pub fn remove_from_store(id: &str) -> Result<()> {
    let dir = paths::store_dir().join(id);
    if dir.exists() {
        std::fs::remove_dir_all(&dir)?;
    }
    Ok(())
}

/// First-touch pristine snapshot of a stock file ($II-relative path).
/// Returns the snapshot path. Does not overwrite an existing snapshot.
pub fn ensure_pristine_snapshot(rel: &str, current_stripped: &str) -> Result<PathBuf> {
    let snap = paths::pristine_dir().join(rel);
    if !snap.exists() {
        if let Some(parent) = snap.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&snap, current_stripped)?;
    }
    Ok(snap)
}

/// Force-refresh a pristine snapshot (used by reapply after a dots update).
pub fn refresh_pristine_snapshot(rel: &str, current_stripped: &str) -> Result<PathBuf> {
    let snap = paths::pristine_dir().join(rel);
    if let Some(parent) = snap.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&snap, current_stripped)?;
    Ok(snap)
}

pub fn read_pristine(rel: &str) -> Option<String> {
    std::fs::read_to_string(paths::pristine_dir().join(rel)).ok()
}

/// A backup set: pre-mutation copies of every file a transaction touches.
pub struct BackupSet {
    pub dir: PathBuf,
}

impl BackupSet {
    pub fn create() -> Result<BackupSet> {
        Self::create_in(&paths::backups_dir())
    }

    pub fn create_in(base: &Path) -> Result<BackupSet> {
        let stamp = format!("{}-{}", crate::registry::now_epoch(), std::process::id());
        let dir = base.join(stamp);
        std::fs::create_dir_all(&dir)?;
        Ok(BackupSet { dir })
    }

    /// Back up an absolute file path, keyed by a stable relative label.
    pub fn add(&self, label: &str, absolute: &Path) -> Result<()> {
        if absolute.exists() {
            let dest = self.dir.join(label);
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(absolute, dest)?;
        }
        Ok(())
    }

    pub fn restore(&self, label: &str, absolute: &Path) -> Result<()> {
        let src = self.dir.join(label);
        if src.exists() {
            if let Some(parent) = absolute.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(src, absolute)?;
        } else if absolute.exists() {
            // File did not exist pre-transaction: restoring means removing it.
            std::fs::remove_file(absolute)?;
        }
        Ok(())
    }
}

/// Keep the newest `keep` backup sets, delete the rest.
pub fn prune_backups(keep: usize) -> Result<()> {
    let dir = paths::backups_dir();
    if !dir.exists() {
        return Ok(());
    }
    let mut entries: Vec<PathBuf> = std::fs::read_dir(&dir)?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    entries.sort();
    while entries.len() > keep {
        let victim = entries.remove(0);
        let _ = std::fs::remove_dir_all(victim);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_and_copy_roundtrip() {
        let base = std::env::temp_dir().join(format!("iimp-store-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let src = base.join("src");
        std::fs::create_dir_all(src.join("nested")).unwrap();
        std::fs::write(src.join("a.qml"), "A").unwrap();
        std::fs::write(src.join("nested/b.qml"), "B").unwrap();

        let dest = base.join("dest");
        copy_tree(&src, &dest).unwrap();
        assert_eq!(hash_tree(&src).unwrap(), hash_tree(&dest).unwrap());
        assert_eq!(hash_tree(&src).unwrap().len(), 2);
    }

    #[test]
    fn backup_restore_including_nonexistent() {
        let base = std::env::temp_dir().join(format!("iimp-bak-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(&base).unwrap();

        let set = BackupSet::create_in(&base.join("backups")).unwrap();
        let existing = base.join("exists.qml");
        std::fs::write(&existing, "original").unwrap();
        set.add("exists.qml", &existing).unwrap();
        let ghost = base.join("ghost.qml");
        set.add("ghost.qml", &ghost).unwrap(); // did not exist

        std::fs::write(&existing, "mutated").unwrap();
        std::fs::write(&ghost, "created during txn").unwrap();

        set.restore("exists.qml", &existing).unwrap();
        set.restore("ghost.qml", &ghost).unwrap();
        assert_eq!(std::fs::read_to_string(&existing).unwrap(), "original");
        assert!(!ghost.exists(), "restore of a pre-nonexistent file must delete it");
    }
}
