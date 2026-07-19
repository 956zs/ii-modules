//! Compatibility probes (SPEC 1.0 §4). Evaluated against fence-stripped stock text.

use std::path::Path;

use anyhow::Result;

use crate::exit::{self, bail};
use crate::manifest::{Probe, ProbeType};
use crate::patch;

pub struct ProbeFailure {
    pub probe: Probe,
    pub detail: String,
}

/// Evaluate all probes against the shell tree at `ii_root`. Returns failures
/// (empty = compatible). IO errors on unreadable-but-existing files are failures too.
pub fn evaluate(ii_root: &Path, probes: &[Probe]) -> Vec<ProbeFailure> {
    let mut failures = Vec::new();
    for probe in probes {
        let target = ii_root.join(&probe.path);
        match probe.probe_type {
            ProbeType::FileExists => {
                if !target.is_file() {
                    failures.push(ProbeFailure {
                        probe: probe.clone(),
                        detail: "file does not exist".into(),
                    });
                }
            }
            ProbeType::FileContains => {
                let pattern = probe.pattern.as_deref().unwrap_or_default();
                match std::fs::read_to_string(&target) {
                    Ok(text) => {
                        // Fence-stripped view: probes must test stock features only.
                        let stripped = patch::strip(&text).map(|(s, _)| s).unwrap_or(text);
                        if !stripped.contains(pattern) {
                            failures.push(ProbeFailure {
                                probe: probe.clone(),
                                detail: format!("pattern {pattern:?} not found"),
                            });
                        }
                    }
                    Err(e) => failures.push(ProbeFailure {
                        probe: probe.clone(),
                        detail: format!("cannot read file: {e}"),
                    }),
                }
            }
        }
    }
    failures
}

/// Convenience: error (exit 4) listing every failure with its declared reason.
pub fn require(ii_root: &Path, probes: &[Probe]) -> Result<()> {
    let failures = evaluate(ii_root, probes);
    if failures.is_empty() {
        return Ok(());
    }
    let mut msg = String::from("compatibility probes failed:\n");
    for f in &failures {
        msg.push_str(&format!(
            "  ✗ {} {} — {} (declared reason: {})\n",
            match f.probe.probe_type {
                ProbeType::FileExists => "file-exists",
                ProbeType::FileContains => "file-contains",
            },
            f.probe.path,
            f.detail,
            f.probe.reason
        ));
    }
    msg.push_str("this module is not compatible with the installed shell revision (no bypass exists)");
    Err(bail(exit::PROBE, msg))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{Probe, ProbeType};

    static DIR_SEQ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

    fn tmp_tree() -> std::path::PathBuf {
        let seq = DIR_SEQ.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("iimp-probe-{}-{}", std::process::id(), seq));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("services")).unwrap();
        std::fs::write(
            dir.join("services/Network.qml"),
            "Singleton {\n    property string materialSymbol: \"lan\"\n}\n",
        )
        .unwrap();
        dir
    }

    fn probe(t: ProbeType, path: &str, pattern: Option<&str>) -> Probe {
        Probe {
            probe_type: t,
            path: path.into(),
            pattern: pattern.map(String::from),
            reason: "test".into(),
        }
    }

    #[test]
    fn exists_and_contains() {
        let root = tmp_tree();
        assert!(require(&root, &[
            probe(ProbeType::FileExists, "services/Network.qml", None),
            probe(ProbeType::FileContains, "services/Network.qml", Some("materialSymbol")),
        ]).is_ok());

        let err = require(&root, &[probe(ProbeType::FileExists, "services/Nope.qml", None)]).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROBE);

        let err = require(&root, &[
            probe(ProbeType::FileContains, "services/Network.qml", Some("does-not-appear")),
        ]).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROBE);
    }

    #[test]
    fn probes_ignore_fenced_content() {
        let root = tmp_tree();
        std::fs::write(
            root.join("services/Network.qml"),
            "Singleton {\n// >>> iimp other/0 v1.0.0 >>>\n    property string sneaky: \"planted\"\n// <<< iimp other/0 <<<\n}\n",
        )
        .unwrap();
        let err = require(&root, &[
            probe(ProbeType::FileContains, "services/Network.qml", Some("sneaky")),
        ]).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROBE, "fenced text must not satisfy probes");
    }
}
