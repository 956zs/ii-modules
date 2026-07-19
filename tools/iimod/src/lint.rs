//! Capability cross-check + payload hygiene lints (SPEC 1.0 §6, §2.2).
//! Grep-class heuristics, documented as such: they raise the honesty bar.

use std::collections::BTreeSet;
use std::path::Path;

use anyhow::Result;
use regex::Regex;
use walkdir::WalkDir;

use crate::exit::{self, bail};
use crate::manifest::{Capability, Manifest, BASENAME_DENYLIST_BASELINE};

pub struct LintReport {
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

fn detectors() -> Vec<(Capability, Regex)> {
    vec![
        (Capability::Exec, Regex::new(r"\bProcess\s*\{|execDetached\s*\(|Hyprland\.dispatch\s*\(").unwrap()),
        (Capability::Network, Regex::new(r"\bXMLHttpRequest\b|\bWebSocket\b|\bSocket\b").unwrap()),
        (Capability::Dbus, Regex::new(r"\bDBus").unwrap()),
        (Capability::FilesystemWrite, Regex::new(r"\.setText\s*\(|writeAdapter\s*\(").unwrap()),
    ]
}

fn strip_comments(qml: &str) -> String {
    // Naive but adequate for a grep-class lint: drop // line tails and /* */ blocks.
    let block = Regex::new(r"(?s)/\*.*?\*/").unwrap();
    let no_blocks = block.replace_all(qml, "");
    no_blocks
        .lines()
        .map(|l| l.split("//").next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n")
}

/// Basenames of stock QML types the module must not shadow. Walks the live tree
/// when available; falls back to the frozen baseline.
pub fn stock_basename_denylist(ii_root: &Path) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    for sub in ["services", "modules/common"] {
        let dir = ii_root.join(sub);
        if dir.is_dir() {
            for entry in WalkDir::new(&dir).into_iter().flatten() {
                if entry.file_type().is_file()
                    && entry.path().extension().is_some_and(|e| e == "qml")
                {
                    set.insert(entry.file_name().to_string_lossy().into_owned());
                }
            }
        }
    }
    if set.is_empty() {
        set.extend(BASENAME_DENYLIST_BASELINE.iter().map(|s| s.to_string()));
    }
    set
}

/// Lint a payload directory against its manifest. `ii_root` is used for the
/// live deny-list (pass a non-existent path to use the baseline).
pub fn lint(manifest: &Manifest, payload: &Path, ii_root: &Path) -> Result<LintReport> {
    let mut errors = Vec::new();
    let mut warnings = Vec::new();

    let denylist = stock_basename_denylist(ii_root);
    let declared: BTreeSet<Capability> = manifest.capabilities.iter().copied().collect();
    let mut detected: BTreeSet<Capability> = BTreeSet::new();

    let own_config_marker = format!("modules/{}.json", manifest.id);
    let singleton_re = Regex::new(r"^\s*pragma\s+Singleton").unwrap();
    let qs_mod_import_re = Regex::new(r"^\s*import\s+qs\.mod\b").unwrap();

    for entry in WalkDir::new(payload).into_iter().flatten() {
        if !entry.file_type().is_file() {
            // Reject symlinks outright (payloads must be plain trees).
            if entry.file_type().is_symlink() {
                errors.push(format!("{}: symlinks are not allowed in payloads", entry.path().display()));
            }
            continue;
        }
        let rel = entry.path().strip_prefix(payload).unwrap().to_string_lossy().into_owned();
        let ext = entry.path().extension().and_then(|e| e.to_str()).unwrap_or_default();

        if ext == "qml" {
            let basename = entry.file_name().to_string_lossy().into_owned();
            if denylist.contains(&basename) {
                errors.push(format!(
                    "{rel}: basename collides with stock type {basename} (would shadow/conflict — rename the file)"
                ));
            }
        }

        if matches!(ext, "qml" | "js") {
            let Ok(text) = std::fs::read_to_string(entry.path()) else { continue };
            let code = strip_comments(&text);
            for line in code.lines() {
                if singleton_re.is_match(line) {
                    errors.push(format!("{rel}: pragma Singleton is forbidden in modules (unregistrable under mod/)"));
                }
                if qs_mod_import_re.is_match(line) {
                    errors.push(format!("{rel}: importing qs.mod.* is forbidden"));
                }
            }
            for (cap, re) in detectors() {
                if re.is_match(&code) {
                    // Blessed exception: the ConfigLoader pattern writing the
                    // module's own config file needs no filesystem-write.
                    if cap == Capability::FilesystemWrite && code.contains(&own_config_marker) {
                        continue;
                    }
                    detected.insert(cap);
                }
            }
        }
    }

    for cap in &detected {
        if !declared.contains(cap) {
            errors.push(format!(
                "capability {:?} detected in code but not declared in manifest.capabilities",
                cap
            ));
        }
    }
    for cap in &declared {
        if !detected.contains(cap) {
            warnings.push(format!("capability {:?} declared but not detected (over-declaration is allowed)", cap));
        }
    }

    Ok(LintReport { errors, warnings })
}

/// Errors → exit 3.
pub fn require_clean(report: &LintReport) -> Result<()> {
    if report.errors.is_empty() {
        return Ok(());
    }
    Err(bail(exit::VALIDATION, format!("lint failed:\n  ✗ {}", report.errors.join("\n  ✗ "))))
}

// ---------------------------------------------------------------------------
// `iimod suggest`: derive probe + capability suggestions from the code
// ---------------------------------------------------------------------------

/// QML/Qt/Quickshell types that never need probes.
const BUILTIN_TYPES: &[&str] = &[
    "Item", "Rectangle", "Text", "Image", "MouseArea", "Timer", "Loader", "Component",
    "Connections", "Repeater", "ListView", "GridView", "Column", "Row", "Grid", "Flow",
    "ColumnLayout", "RowLayout", "GridLayout", "Layout", "StackLayout", "Behavior",
    "NumberAnimation", "ColorAnimation", "PropertyAnimation", "SequentialAnimation",
    "ParallelAnimation", "PropertyAction", "State", "Transition", "Canvas", "TextMetrics",
    "FontMetrics", "Flickable", "ScrollView", "Shortcut", "QtObject", "Binding",
    "Process", "FileView", "JsonObject", "JsonAdapter", "Singleton", "Scope",
    "PanelWindow", "LazyLoader", "IpcHandler", "StdioCollector", "SplitParser",
    "Variants", "ShellRoot", "PersistentProperties", "ScriptModel", "FileViewError",
    "Qt", "JSON", "Math", "Date", "Object", "Array", "String", "Number", "Boolean",
    "RegExp", "Component", "Screen", "Window",
    "Config", "Appearance", "Directories", "Translation", // guaranteed baseline
];

pub struct Suggestions {
    pub probes: Vec<(String, String)>, // (path, reason)
    pub capabilities: Vec<Capability>,
    pub notes: Vec<String>,
}

/// Scan a payload for stock-type usage and detectable capabilities; map each
/// non-baseline type to its stock file in the live tree for a file-exists probe.
pub fn suggest(payload: &Path, ii_root: &Path) -> Result<Suggestions> {
    let type_use = Regex::new(r"\b([A-Z][A-Za-z0-9]+)\s*[.{]").unwrap();
    let own_id = payload.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let own_config_marker = format!("modules/{own_id}.json");
    let mut candidates: BTreeSet<String> = BTreeSet::new();
    let mut detected: BTreeSet<Capability> = BTreeSet::new();

    for entry in WalkDir::new(payload).into_iter().flatten() {
        if !entry.file_type().is_file() {
            continue;
        }
        let ext = entry.path().extension().and_then(|e| e.to_str()).unwrap_or_default();
        if !matches!(ext, "qml" | "js") {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(entry.path()) else { continue };
        let code = strip_comments(&text);
        // Import lines carry module URIs (QtQuick.Layouts, qs.services…), not type usage.
        let code_no_imports: String = code
            .lines()
            .filter(|l| !l.trim_start().starts_with("import "))
            .collect::<Vec<_>>()
            .join("\n");
        for cap in type_use.captures_iter(&code_no_imports) {
            let name = cap[1].to_string();
            if !BUILTIN_TYPES.contains(&name.as_str()) {
                candidates.insert(name);
            }
        }
        for (capability, re) in detectors() {
            if re.is_match(&code_no_imports) {
                // Same blessed exemption as lint(): the module's own ConfigLoader.
                if capability == Capability::FilesystemWrite && code.contains(&own_config_marker) {
                    continue;
                }
                detected.insert(capability);
            }
        }
    }

    // Locate each candidate as a stock file; own payload files are excluded
    // (a module's own siblings need no probes).
    let own: BTreeSet<String> = WalkDir::new(payload)
        .into_iter()
        .flatten()
        .filter(|e| e.file_type().is_file())
        .map(|e| e.file_name().to_string_lossy().trim_end_matches(".qml").to_string())
        .collect();

    let mut probes = Vec::new();
    let mut notes = Vec::new();
    for name in candidates {
        if own.contains(&name) {
            continue;
        }
        let mut found = None;
        let mut baseline = false;
        'search: for sub in ["services", "modules"] {
            let base = ii_root.join(sub);
            if !base.is_dir() {
                continue;
            }
            for entry in WalkDir::new(&base).into_iter().flatten() {
                if entry.file_type().is_file()
                    && entry.file_name().to_string_lossy() == format!("{name}.qml")
                {
                    let rel = entry.path().strip_prefix(ii_root).unwrap().to_string_lossy().into_owned();
                    if rel.starts_with("modules/common/") {
                        baseline = true; // guaranteed baseline: silently exempt
                    } else {
                        found = Some(rel);
                    }
                    break 'search;
                }
            }
        }
        if baseline {
            continue;
        }
        match found {
            Some(rel) => probes.push((rel, format!("uses stock type {name}"))),
            None => notes.push(format!("type {name} not found in stock tree (module-local or a missed builtin — verify manually)")),
        }
    }
    probes.sort();
    probes.dedup();
    Ok(Suggestions { probes, capabilities: detected.into_iter().collect(), notes })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest;

    static DIR_SEQ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

    fn payload_with(files: &[(&str, &str)]) -> std::path::PathBuf {
        let seq = DIR_SEQ.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("iimp-lint-{}-{}", std::process::id(), seq));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        for (name, content) in files {
            let p = dir.join(name);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, content).unwrap();
        }
        dir
    }

    fn minimal_manifest(caps: &[Capability]) -> Manifest {
        let mut m: Manifest =
            serde_json::from_str(include_str!("../../../spec/fixtures/valid/tier-a-minimal.json")).unwrap();
        m.capabilities = caps.to_vec();
        m
    }

    #[test]
    fn undeclared_exec_is_error() {
        let payload = payload_with(&[("bar.qml", "Item { Process { command: [\"rm\"] } }")]);
        let report = lint(&minimal_manifest(&[]), &payload, std::path::Path::new("/nonexistent")).unwrap();
        assert!(report.errors.iter().any(|e| e.contains("Exec")));
        assert!(require_clean(&report).is_err());
    }

    #[test]
    fn declared_exec_is_clean_and_comments_ignored() {
        let payload = payload_with(&[("bar.qml", "Item { Process {} } // XMLHttpRequest in comment only")]);
        let report = lint(&minimal_manifest(&[Capability::Exec]), &payload, std::path::Path::new("/nonexistent")).unwrap();
        assert!(report.errors.is_empty(), "{:?}", report.errors);
    }

    #[test]
    fn blessed_config_loader_is_exempt() {
        let payload = payload_with(&[(
            "ConfigLoader.qml",
            "FileView { path: root.base + \"/modules/hello-bar.json\"\n onAdapterUpdated: writeAdapter() }",
        )]);
        let report = lint(&minimal_manifest(&[]), &payload, std::path::Path::new("/nonexistent")).unwrap();
        assert!(report.errors.is_empty(), "{:?}", report.errors);
    }

    #[test]
    fn denylist_and_singleton_and_qs_mod_import() {
        let payload = payload_with(&[
            ("Config.qml", "Item {}"),
            ("logic.qml", "pragma Singleton\nItem {}"),
            ("other.qml", "import qs.mod.friend\nItem {}"),
        ]);
        let report = lint(&minimal_manifest(&[]), &payload, std::path::Path::new("/nonexistent")).unwrap();
        assert!(report.errors.iter().any(|e| e.contains("collides with stock type")));
        assert!(report.errors.iter().any(|e| e.contains("pragma Singleton")));
        assert!(report.errors.iter().any(|e| e.contains("qs.mod")));
    }
}
