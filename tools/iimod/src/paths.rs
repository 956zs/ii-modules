//! Filesystem roots. `IIMOD_II_ROOT` / `IIMOD_STATE_ROOT` / `IIMOD_SHELLCONFIG_ROOT`
//! environment overrides exist for the integration test harness so the tool can
//! operate on a copy of the live tree (SPEC §8).

use std::path::PathBuf;

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").expect("HOME is not set"))
}

/// The Quickshell config tree ($II).
pub fn ii_root() -> PathBuf {
    std::env::var_os("IIMOD_II_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config/quickshell/ii"))
}

/// Authoritative state root, outside the wipe zone.
pub fn state_root() -> PathBuf {
    std::env::var_os("IIMOD_STATE_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share/iimp"))
}

/// ~/.config/illogical-impulse (shell config dir: projections, translations).
pub fn shell_config_root() -> PathBuf {
    std::env::var_os("IIMOD_SHELLCONFIG_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config/illogical-impulse"))
}

pub fn mod_root() -> PathBuf {
    ii_root().join("mod")
}

pub fn host_dir() -> PathBuf {
    mod_root().join("iimp")
}

pub fn host_sentinel() -> PathBuf {
    host_dir().join(".iimp-host")
}

pub fn registry_path() -> PathBuf {
    state_root().join("registry.json")
}

pub fn lock_path() -> PathBuf {
    state_root().join("lock")
}

pub fn journal_path() -> PathBuf {
    state_root().join("journal.json")
}

pub fn store_dir() -> PathBuf {
    state_root().join("store")
}

pub fn pristine_dir() -> PathBuf {
    state_root().join("pristine")
}

pub fn backups_dir() -> PathBuf {
    state_root().join("backups")
}

pub fn tmp_dir() -> PathBuf {
    state_root().join("tmp")
}

pub fn modules_config_dir() -> PathBuf {
    shell_config_root().join("modules")
}

pub fn index_projection_path() -> PathBuf {
    modules_config_dir().join("index.json")
}

pub fn translations_dir() -> PathBuf {
    shell_config_root().join("translations")
}
