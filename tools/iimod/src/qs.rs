//! Quickshell interaction: IPC with env scrubbing (fish exports
//! QT_QPA_PLATFORM=xcb globally on this setup), reload triggering, never pkill.

use std::process::Command;

/// Test/CI escape hatch: IIMOD_NO_QS=1 turns every qs interaction into a no-op
/// (integration tests must never IPC into the developer's live session).
pub fn disabled() -> bool {
    std::env::var_os("IIMOD_NO_QS").is_some_and(|v| v == "1")
}

fn qs_command() -> Command {
    let mut cmd = Command::new("qs");
    // The ipc client resolves instances per display; xcb env would look in the
    // wrong bucket. --any-display below is the belt, this is the suspenders.
    cmd.env_remove("QT_QPA_PLATFORM");
    cmd
}

pub fn ipc_call(args: &[&str]) -> Option<String> {
    if disabled() {
        return None;
    }
    let output = qs_command()
        .args(["-c", "ii", "ipc", "--any-display", "call"])
        .args(args)
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

/// Is a shell instance with the host running?
pub fn ping() -> bool {
    ipc_call(&["iimp", "ping"]).as_deref() == Some("pong")
}

/// Any ii instance running at all (host or not)?
pub fn shell_running() -> bool {
    if disabled() {
        return false;
    }
    let output = qs_command().args(["list", "--all"]).output();
    match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).contains("Config path:"),
        Err(_) => false,
    }
}

pub fn set_enabled(id: &str, slot: &str, on: bool) -> bool {
    ipc_call(&["iimp", "setEnabled", id, slot, if on { "true" } else { "false" }]).is_some()
}

/// Best-effort reload. Order: host IPC reload → byte-identical shell.qml rewrite
/// (close-write fires the file watcher regardless of content). Never an error:
/// Quickshell keeps the previous config alive on reload failure.
pub fn trigger_reload() -> bool {
    if disabled() {
        return true;
    }
    if ipc_call(&["iimp", "reload"]).is_some() {
        return true;
    }
    let shell_qml = crate::paths::ii_root().join("shell.qml");
    if let Ok(bytes) = std::fs::read(&shell_qml) {
        if std::fs::write(&shell_qml, bytes).is_ok() {
            return true;
        }
    }
    false
}

pub fn qs_version() -> Option<String> {
    if disabled() {
        return None;
    }
    let output = qs_command().arg("--version").output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    text.lines().next().map(|l| l.trim().to_string())
}
