//! module.json parsing and validation (SPEC 1.0 §3). serde with
//! deny_unknown_fields IS the schema; validators enforce everything serde can't.

use std::collections::BTreeMap;
use std::path::Path;

use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::exit::{self, bail};

pub const SUPPORTED_PROTOCOL_MIN: u32 = 1;
pub const SUPPORTED_PROTOCOL_MAX: u32 = 1;

pub const RESERVED_IDS: &[&str] = &["iimp", "host", "all", "none", "common", "stock", "settings"];

/// Frozen fallback deny-list of stock QML basenames (used when the live tree is
/// unavailable at validation time). The live tree walk supersedes this.
pub const BASENAME_DENYLIST_BASELINE: &[&str] = &[
    "Config.qml",
    "Appearance.qml",
    "Directories.qml",
    "Persistent.qml",
    "GlobalStates.qml",
    "Network.qml",
    "Translation.qml",
    "ResourceUsage.qml",
    "NetworkTraffic.qml",
    "Battery.qml",
    "Notifications.qml",
    "StyledText.qml",
    "MaterialSymbol.qml",
    "StyledPopup.qml",
    "Graph.qml",
    "Wallpapers.qml",
];

pub type LocalizedString = BTreeMap<String, String>;

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Manifest {
    pub protocol_version: u32,
    pub id: String,
    pub name: LocalizedString,
    pub description: LocalizedString,
    pub version: String,
    pub authors: Vec<String>,
    pub license: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub homepage: Option<String>,
    pub slots: Vec<Slot>,
    #[serde(default)]
    pub entries: Entries,
    pub compat: Compat,
    #[serde(default)]
    pub requires: Requires,
    #[serde(default)]
    pub conflicts: Vec<String>,
    pub capabilities: Vec<Capability>,
    #[serde(default)]
    pub patches: Vec<Patch>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Slot {
    Bar,
    Window,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Entries {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bar: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub settings: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Compat {
    pub probes: Vec<Probe>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tested_on: Option<TestedOn>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Probe {
    #[serde(rename = "type")]
    pub probe_type: ProbeType,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pattern: Option<String>,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
pub enum ProbeType {
    #[serde(rename = "file-exists")]
    FileExists,
    #[serde(rename = "file-contains")]
    FileContains,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct TestedOn {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dots_commit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qs_version: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Requires {
    #[serde(default)]
    pub modules: Vec<ModuleReq>,
    #[serde(default)]
    pub system: Vec<SystemReq>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ModuleReq {
    pub id: String,
    pub version_req: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SystemReq {
    pub bin: String,
    pub hint: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Capability {
    Exec,
    Network,
    FilesystemWrite,
    Dbus,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Patch {
    pub file: String,
    pub op: PatchOp,
    pub anchor: String,
    pub content: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PatchOp {
    InsertAfter,
    InsertBefore,
}

impl Manifest {
    pub fn is_tier_b(&self) -> bool {
        !self.patches.is_empty()
    }

    pub fn semver(&self) -> Result<semver::Version> {
        semver::Version::parse(&self.version)
            .map_err(|e| bail(exit::VALIDATION, format!("version: not strict semver: {e}")))
    }

    pub fn entry_for(&self, slot: Slot) -> &str {
        match slot {
            Slot::Bar => self.entries.bar.as_deref().unwrap_or("bar.qml"),
            Slot::Window => self.entries.window.as_deref().unwrap_or("main.qml"),
        }
    }
}

pub fn is_valid_locale(key: &str) -> bool {
    let bytes = key.as_bytes();
    let Some(us) = key.find('_') else {
        return false;
    };
    let (lang, region) = (&bytes[..us], &bytes[us + 1..]);
    (2..=3).contains(&lang.len())
        && lang.iter().all(u8::is_ascii_lowercase)
        && region.len() == 2
        && region.iter().all(u8::is_ascii_uppercase)
}

/// Ids are QML-URI segments: the module dir must be importable as
/// `qs.mod.<id>` for sibling type resolution (path-loaded files get no
/// implicit same-directory types under Quickshell's URL interceptor), and QML
/// URIs forbid hyphens — hence underscores.
pub fn is_valid_id(id: &str) -> bool {
    let bytes = id.as_bytes();
    if !(2..=31).contains(&bytes.len()) {
        return false;
    }
    if !bytes[0].is_ascii_lowercase() {
        return false;
    }
    if !bytes
        .iter()
        .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'_')
    {
        return false;
    }
    !id.ends_with('_') && !id.contains("__")
}

/// A path relative to a root: no `..`, not absolute, no `~`, non-empty, UTF-8 clean.
pub fn is_safe_rel_path(p: &str) -> bool {
    if p.is_empty() || p.starts_with('/') || p.starts_with('~') || p.contains('\0') {
        return false;
    }
    !Path::new(p).components().any(|c| {
        matches!(
            c,
            std::path::Component::ParentDir | std::path::Component::RootDir
        )
    })
}

fn validate_localized(field: &str, m: &LocalizedString, max_en: Option<usize>) -> Result<()> {
    let Some(en) = m.get("en_US") else {
        return Err(bail(
            exit::VALIDATION,
            format!("{field}: en_US key is required"),
        ));
    };
    if en.trim().is_empty() {
        return Err(bail(
            exit::VALIDATION,
            format!("{field}.en_US: must be non-empty"),
        ));
    }
    if let Some(max) = max_en {
        if en.chars().count() > max {
            return Err(bail(
                exit::VALIDATION,
                format!("{field}.en_US: exceeds {max} chars"),
            ));
        }
    }
    for key in m.keys() {
        if !is_valid_locale(key) {
            return Err(bail(
                exit::VALIDATION,
                format!("{field}: invalid locale key {key:?}"),
            ));
        }
    }
    Ok(())
}

const FENCE_MARKER_HINTS: [&str; 2] = [">>> iimp ", "<<< iimp "];

/// Warnings that don't block; errors are returned as ExitError(VALIDATION/PROTOCOL).
pub fn validate(manifest: &Manifest) -> Result<Vec<String>> {
    let mut warnings = Vec::new();

    // Protocol range gates everything else (SPEC §11).
    if manifest.protocol_version < SUPPORTED_PROTOCOL_MIN
        || manifest.protocol_version > SUPPORTED_PROTOCOL_MAX
    {
        return Err(bail(
            exit::PROTOCOL,
            format!(
                "protocolVersion {} unsupported (this iimod supports {}..={}); upgrade or downgrade iimod",
                manifest.protocol_version, SUPPORTED_PROTOCOL_MIN, SUPPORTED_PROTOCOL_MAX
            ),
        ));
    }

    if !is_valid_id(&manifest.id) {
        return Err(bail(
            exit::VALIDATION,
            format!(
                "id {:?}: must match ^[a-z][a-z0-9_]{{1,30}}$ with no trailing '_' or '__'",
                manifest.id
            ),
        ));
    }
    if RESERVED_IDS.contains(&manifest.id.as_str()) {
        return Err(bail(
            exit::VALIDATION,
            format!("id {:?} is reserved", manifest.id),
        ));
    }

    validate_localized("name", &manifest.name, Some(40))?;
    validate_localized("description", &manifest.description, None)?;

    let version = manifest.semver()?;
    if !version.pre.is_empty() {
        warnings.push(format!("version {} is a prerelease", version));
    }

    if manifest.authors.is_empty() {
        return Err(bail(exit::VALIDATION, "authors: must be non-empty"));
    }
    if !manifest
        .license
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || ".+-".contains(c))
    {
        warnings.push(format!(
            "license {:?} does not look like an SPDX token",
            manifest.license
        ));
    }
    if let Some(hp) = &manifest.homepage {
        if !(hp.starts_with("http://") || hp.starts_with("https://")) {
            return Err(bail(
                exit::VALIDATION,
                "homepage: must start with http:// or https://",
            ));
        }
    }

    if manifest.slots.is_empty() {
        return Err(bail(exit::VALIDATION, "slots: must be non-empty"));
    }
    {
        let mut seen = Vec::new();
        for slot in &manifest.slots {
            if seen.contains(slot) {
                return Err(bail(exit::VALIDATION, "slots: duplicate entries"));
            }
            seen.push(*slot);
        }
    }

    for (label, entry) in [
        ("entries.bar", &manifest.entries.bar),
        ("entries.window", &manifest.entries.window),
        ("entries.settings", &manifest.entries.settings),
    ] {
        if let Some(e) = entry {
            if !is_safe_rel_path(e) || !e.ends_with(".qml") {
                return Err(bail(
                    exit::VALIDATION,
                    format!("{label}: must be a safe relative .qml path"),
                ));
            }
        }
    }

    // Probes.
    for (i, probe) in manifest.compat.probes.iter().enumerate() {
        let ctx = format!("compat.probes[{i}]");
        if !is_safe_rel_path(&probe.path) || probe.path.starts_with("mod/") {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.path: must be a safe path under $II, not under mod/"),
            ));
        }
        match probe.probe_type {
            ProbeType::FileContains => {
                let Some(pattern) = &probe.pattern else {
                    return Err(bail(
                        exit::VALIDATION,
                        format!("{ctx}: file-contains requires pattern"),
                    ));
                };
                if pattern.chars().count() < 6 {
                    return Err(bail(
                        exit::VALIDATION,
                        format!("{ctx}.pattern: minimum 6 characters"),
                    ));
                }
                if pattern.contains('\n') {
                    return Err(bail(
                        exit::VALIDATION,
                        format!("{ctx}.pattern: must be single-line"),
                    ));
                }
            }
            ProbeType::FileExists => {
                if probe.pattern.is_some() {
                    return Err(bail(
                        exit::VALIDATION,
                        format!("{ctx}: file-exists takes no pattern"),
                    ));
                }
            }
        }
        if probe.reason.trim().is_empty() {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.reason: must be non-empty"),
            ));
        }
    }
    if let Some(t) = &manifest.compat.tested_on {
        if let Some(c) = &t.dots_commit {
            let ok = (7..=40).contains(&c.len())
                && c.chars()
                    .all(|ch| ch.is_ascii_hexdigit() && !ch.is_ascii_uppercase());
            if !ok {
                return Err(bail(
                    exit::VALIDATION,
                    "compat.testedOn.dotsCommit: must be 7-40 lowercase hex chars",
                ));
            }
        }
    }

    // Requires.
    let mut dep_ids = Vec::new();
    for (i, dep) in manifest.requires.modules.iter().enumerate() {
        let ctx = format!("requires.modules[{i}]");
        if !is_valid_id(&dep.id) {
            return Err(bail(exit::VALIDATION, format!("{ctx}.id: invalid id")));
        }
        if dep.id == manifest.id {
            return Err(bail(exit::VALIDATION, format!("{ctx}: self-dependency")));
        }
        if dep_ids.contains(&dep.id) {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}: duplicate dependency id"),
            ));
        }
        dep_ids.push(dep.id.clone());
        semver::VersionReq::parse(&dep.version_req)
            .map_err(|e| bail(exit::VALIDATION, format!("{ctx}.versionReq: {e}")))?;
    }
    for (i, s) in manifest.requires.system.iter().enumerate() {
        if s.bin.is_empty() || s.bin.contains('/') {
            return Err(bail(
                exit::VALIDATION,
                format!("requires.system[{i}].bin: must be a bare binary name"),
            ));
        }
        if s.hint.trim().is_empty() {
            return Err(bail(
                exit::VALIDATION,
                format!("requires.system[{i}].hint: must be non-empty"),
            ));
        }
    }

    for (i, c) in manifest.conflicts.iter().enumerate() {
        if !is_valid_id(c) {
            return Err(bail(
                exit::VALIDATION,
                format!("conflicts[{i}]: invalid id"),
            ));
        }
        if *c == manifest.id {
            return Err(bail(
                exit::VALIDATION,
                format!("conflicts[{i}]: self-conflict"),
            ));
        }
    }

    // Patches (Tier B).
    for (i, patch) in manifest.patches.iter().enumerate() {
        let ctx = format!("patches[{i}]");
        if !is_safe_rel_path(&patch.file) {
            return Err(bail(exit::VALIDATION, format!("{ctx}.file: unsafe path")));
        }
        if patch.file.starts_with("mod/") || patch.file == "mod" {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.file: patches may not target mod/"),
            ));
        }
        if !patch.file.ends_with(".qml") {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.file: only .qml stock files may be patched in protocolVersion 1"),
            ));
        }
        if patch.anchor.chars().count() < 10 {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.anchor: minimum 10 characters"),
            ));
        }
        if patch.anchor.contains('\n') {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.anchor: must be single-line"),
            ));
        }
        if patch.content.is_empty() {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.content: must be non-empty"),
            ));
        }
        if patch.content.contains('\r') || patch.content.contains('\0') {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.content: must be LF-only UTF-8 without NUL"),
            ));
        }
        if patch.content.lines().count() > 200 {
            return Err(bail(
                exit::VALIDATION,
                format!("{ctx}.content: exceeds 200 lines"),
            ));
        }
        for line in patch.content.lines() {
            if FENCE_MARKER_HINTS.iter().any(|m| line.contains(m)) {
                return Err(bail(
                    exit::VALIDATION,
                    format!("{ctx}.content: contains fence-marker-like line (injection guard)"),
                ));
            }
        }
    }

    Ok(warnings)
}

/// Parse manifest bytes; serde errors (including unknown fields) map to VALIDATION —
/// except an out-of-range protocolVersion, which callers detect via `validate`.
pub fn parse(bytes: &[u8]) -> Result<Manifest> {
    // Pre-scan protocolVersion loosely so a v2 manifest with new fields reports
    // exit 10 (unsupported protocol) rather than exit 3 (unknown field).
    if let Ok(loose) = serde_json::from_slice::<serde_json::Value>(bytes) {
        if let Some(pv) = loose.get("protocolVersion").and_then(|v| v.as_u64()) {
            let pv = pv as u32;
            if !(SUPPORTED_PROTOCOL_MIN..=SUPPORTED_PROTOCOL_MAX).contains(&pv) {
                return Err(bail(
                    exit::PROTOCOL,
                    format!(
                        "protocolVersion {pv} unsupported (this iimod supports {}..={}); upgrade or downgrade iimod",
                        SUPPORTED_PROTOCOL_MIN, SUPPORTED_PROTOCOL_MAX
                    ),
                ));
            }
        }
    }
    serde_json::from_slice(bytes).map_err(|e| bail(exit::VALIDATION, format!("module.json: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> Vec<u8> {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/fixtures");
        std::fs::read(root.join(name)).unwrap()
    }

    fn parse_valid(name: &str) -> Manifest {
        let m = parse(&fixture(name)).unwrap();
        validate(&m).unwrap();
        m
    }

    #[test]
    fn fixtures_valid() {
        let a = parse_valid("valid/tier-a-minimal.json");
        assert!(!a.is_tier_b());
        assert_eq!(a.entry_for(Slot::Bar), "bar.qml");
        let b = parse_valid("valid/tier-b-full.json");
        assert!(b.is_tier_b());
    }

    fn mutate(base: &str, f: impl FnOnce(&mut serde_json::Value)) -> Result<Vec<String>> {
        let mut v: serde_json::Value = serde_json::from_slice(&fixture(base)).unwrap();
        f(&mut v);
        let m = parse(&serde_json::to_vec(&v).unwrap())?;
        validate(&m)
    }

    fn expect_code(result: Result<Vec<String>>, code: i32) {
        let err = result.unwrap_err();
        assert_eq!(crate::exit::code_of(&err), code, "{err}");
    }

    #[test]
    fn rejects_unknown_field() {
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["surprise"] = "field".into();
            }),
            crate::exit::VALIDATION,
        );
    }

    #[test]
    fn protocol_v2_is_exit_10_even_with_unknown_fields() {
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["protocolVersion"] = 2.into();
                v["newV2Field"] = true.into();
            }),
            crate::exit::PROTOCOL,
        );
    }

    #[test]
    fn id_rules() {
        for bad in [
            "A-upper",
            "has-hyphen",
            "_lead",
            "trail_",
            "dou__ble",
            "x",
            "iimp",
            "settings",
            "waaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaay_too_long_for_the_spec",
        ] {
            expect_code(
                mutate("valid/tier-a-minimal.json", |v| {
                    v["id"] = bad.into();
                }),
                crate::exit::VALIDATION,
            );
        }
    }

    #[test]
    fn name_needs_en_us() {
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["name"] = serde_json::json!({"zh_TW": "只有中文"});
            }),
            crate::exit::VALIDATION,
        );
    }

    #[test]
    fn bad_locale_key() {
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["name"]["EN_us"] = "bad".into();
            }),
            crate::exit::VALIDATION,
        );
    }

    #[test]
    fn strict_semver() {
        for bad in ["1.2", "v1.2.3", "1.2.3.4", "latest"] {
            expect_code(
                mutate("valid/tier-a-minimal.json", |v| {
                    v["version"] = bad.into();
                }),
                crate::exit::VALIDATION,
            );
        }
        let warnings = mutate("valid/tier-a-minimal.json", |v| {
            v["version"] = "1.0.0-rc.1".into();
        })
        .unwrap();
        assert!(warnings.iter().any(|w| w.contains("prerelease")));
    }

    #[test]
    fn slot_entry_and_probe_rules() {
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["slots"] = serde_json::json!([]);
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["slots"] = serde_json::json!(["bar", "bar"]);
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["compat"]["probes"][1]["pattern"] = "tiny".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["compat"]["probes"][0]["path"] = "mod/other/x.qml".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["compat"]["probes"][0]["path"] = "../escape.qml".into();
            }),
            crate::exit::VALIDATION,
        );
    }

    #[test]
    fn requires_rules() {
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["requires"]["modules"][0]["versionReq"] = "not-a-req".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["requires"]["modules"][0]["id"] = "traffic-deluxe".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["requires"]["system"][0]["bin"] = "/usr/bin/jq".into();
            }),
            crate::exit::VALIDATION,
        );
    }

    #[test]
    fn patch_rules() {
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["patches"][0]["file"] = "mod/iimp/ModuleHost.qml".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["patches"][0]["file"] = "scripts/thing.sh".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["patches"][0]["anchor"] = "short".into();
            }),
            crate::exit::VALIDATION,
        );
        expect_code(
            mutate("valid/tier-b-full.json", |v| {
                v["patches"][0]["content"] = "// >>> iimp evil/0 v1.0.0 >>>\n".into();
            }),
            crate::exit::VALIDATION,
        );
    }

    #[test]
    fn capability_enum_strict() {
        expect_code(
            mutate("valid/tier-a-minimal.json", |v| {
                v["capabilities"] = serde_json::json!(["root-access"]);
            }),
            crate::exit::VALIDATION,
        );
    }
}
