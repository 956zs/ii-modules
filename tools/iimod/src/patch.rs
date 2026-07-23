//! Fence grammar + recomposition engine (SPEC 1.0 §7).
//!
//! Laws (tested below):
//!   1. strip(compose(s, P)) == s
//!   2. compose is a pure function of (s, P) — install order never matters
//!   3. anchors resolve only against stripped text

use anyhow::Result;
use regex::Regex;

use crate::exit::{self, bail};
use crate::manifest::PatchOp;

/// One patch as applied on disk, owned by a module (or "host").
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PatchInstance {
    pub owner: String,
    pub index: u32,
    pub version: String,
    pub op: PatchOp,
    pub anchor: String,
    pub content: String,
}

impl PatchInstance {
    fn sort_key(&self) -> (String, u32) {
        (self.owner.clone(), self.index)
    }
}

fn fence_regexes() -> (Regex, Regex) {
    // Owner charset covers module ids (lowercase + digits + underscore) plus
    // "host"; hyphen kept for grammar robustness against older fences.
    let open = Regex::new(r"^\s*// >>> iimp ([a-z0-9_-]+)/(\d+) v(\S+) >>>\s*$").unwrap();
    let close = Regex::new(r"^\s*// <<< iimp ([a-z0-9_-]+)/(\d+) <<<\s*$").unwrap();
    (open, close)
}

/// A fenced block found in a file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FoundBlock {
    pub owner: String,
    pub index: u32,
    pub version: String,
    pub content: String,
}

/// Remove all well-formed fenced blocks. Errors (fence-broken) on: stray close,
/// unclosed open, nested open, or mismatched close identity.
pub fn strip(text: &str) -> Result<(String, Vec<FoundBlock>)> {
    let (open_re, close_re) = fence_regexes();
    let mut out = String::with_capacity(text.len());
    let mut blocks = Vec::new();
    let mut current: Option<(String, u32, String, String)> = None;

    for line in text.split_inclusive('\n') {
        let bare = line.strip_suffix('\n').unwrap_or(line);
        if let Some(caps) = open_re.captures(bare) {
            if current.is_some() {
                return Err(bail(exit::STATE, "fence-broken: nested fence open"));
            }
            current = Some((
                caps[1].to_string(),
                caps[2]
                    .parse()
                    .map_err(|_| bail(exit::STATE, "fence-broken: bad index"))?,
                caps[3].to_string(),
                String::new(),
            ));
        } else if let Some(caps) = close_re.captures(bare) {
            let Some((owner, index, version, content)) = current.take() else {
                return Err(bail(exit::STATE, "fence-broken: close without open"));
            };
            if caps[1] != owner || caps[2].parse::<u32>().ok() != Some(index) {
                return Err(bail(exit::STATE, "fence-broken: close identity mismatch"));
            }
            blocks.push(FoundBlock {
                owner,
                index,
                version,
                content,
            });
        } else if let Some((.., content)) = current.as_mut() {
            content.push_str(line);
        } else {
            out.push_str(line);
        }
    }
    if current.is_some() {
        return Err(bail(exit::STATE, "fence-broken: unclosed fence at EOF"));
    }
    Ok((out, blocks))
}

fn leading_whitespace(line: &str) -> &str {
    &line[..line.len() - line.trim_start().len()]
}

fn render_block(patch: &PatchInstance, indent: &str) -> String {
    let mut block = String::new();
    block.push_str(&format!(
        "{indent}// >>> iimp {}/{} v{} >>>\n",
        patch.owner, patch.index, patch.version
    ));
    block.push_str(&patch.content);
    if !patch.content.ends_with('\n') {
        block.push('\n');
    }
    block.push_str(&format!(
        "{indent}// <<< iimp {}/{} <<<\n",
        patch.owner, patch.index
    ));
    block
}

/// Compose stripped stock text with a patch set. Every anchor must match exactly
/// one line of the stripped text (0 → ANCHOR "not found", ≥2 → ANCHOR "ambiguous").
pub fn compose(stripped: &str, patches: &[PatchInstance]) -> Result<String> {
    let lines: Vec<&str> = stripped.split_inclusive('\n').collect();

    // Resolve every patch to its unique anchor line first (all-or-nothing).
    let mut resolved: Vec<(usize, &PatchInstance)> = Vec::with_capacity(patches.len());
    for patch in patches {
        let matches: Vec<usize> = lines
            .iter()
            .enumerate()
            .filter(|(_, l)| l.contains(&patch.anchor))
            .map(|(i, _)| i)
            .collect();
        match matches.len() {
            1 => resolved.push((matches[0], patch)),
            0 => {
                return Err(bail(
                    exit::ANCHOR,
                    format!(
                        "anchor not found for {}/{}: {:?}",
                        patch.owner, patch.index, patch.anchor
                    ),
                ))
            }
            n => {
                return Err(bail(
                    exit::ANCHOR,
                    format!(
                        "anchor ambiguous ({n} matches) for {}/{}: {:?}",
                        patch.owner, patch.index, patch.anchor
                    ),
                ))
            }
        }
    }

    // Group by (line, op) and order deterministically by (owner, index).
    let mut out = String::with_capacity(stripped.len() * 2);
    for (line_no, line) in lines.iter().enumerate() {
        let indent = leading_whitespace(line.trim_end_matches('\n'));
        let mut before: Vec<&PatchInstance> = resolved
            .iter()
            .filter(|(l, p)| *l == line_no && p.op == PatchOp::InsertBefore)
            .map(|(_, p)| *p)
            .collect();
        before.sort_by_key(|p| p.sort_key());
        for patch in before {
            out.push_str(&render_block(patch, indent));
        }

        out.push_str(line);

        let mut after: Vec<&PatchInstance> = resolved
            .iter()
            .filter(|(l, p)| *l == line_no && p.op == PatchOp::InsertAfter)
            .map(|(_, p)| *p)
            .collect();
        after.sort_by_key(|p| p.sort_key());
        for patch in after {
            // Guarantee the anchor line is newline-terminated before appending a block.
            if !out.ends_with('\n') {
                out.push('\n');
            }
            out.push_str(&render_block(patch, indent));
        }
    }
    Ok(out)
}

/// Full recomposition of a file's bytes: strip whatever is there, re-compose
/// with the given surviving patch set.
pub fn recompose(current: &str, patches: &[PatchInstance]) -> Result<String> {
    let (stripped, _) = strip(current)?;
    compose(&stripped, patches)
}

#[cfg(test)]
mod tests {
    use super::*;

    const STOCK: &str = "import QtQuick\n\nItem {\n    // Weather\n    Loader {}\n    property string panelFamily: \"ii\"\n}\n";

    fn patch(owner: &str, index: u32, op: PatchOp, anchor: &str, content: &str) -> PatchInstance {
        PatchInstance {
            owner: owner.into(),
            index,
            version: "1.0.0".into(),
            op,
            anchor: anchor.into(),
            content: content.into(),
        }
    }

    #[test]
    fn strip_compose_identity() {
        let sets = vec![
            vec![],
            vec![patch(
                "aaa",
                0,
                PatchOp::InsertBefore,
                "// Weather",
                "    AaaThing {}\n",
            )],
            vec![
                patch(
                    "aaa",
                    0,
                    PatchOp::InsertBefore,
                    "// Weather",
                    "    AaaThing {}\n",
                ),
                patch(
                    "bbb",
                    0,
                    PatchOp::InsertAfter,
                    "panelFamily",
                    "    property bool b: true\n",
                ),
                patch(
                    "bbb",
                    1,
                    PatchOp::InsertBefore,
                    "// Weather",
                    "    BbbThing {}\n",
                ),
            ],
        ];
        for set in sets {
            let composed = compose(STOCK, &set).unwrap();
            let (stripped, blocks) = strip(&composed).unwrap();
            assert_eq!(stripped, STOCK, "identity violated");
            assert_eq!(blocks.len(), set.len());
        }
    }

    #[test]
    fn order_independence() {
        let a = patch(
            "aaa",
            0,
            PatchOp::InsertBefore,
            "// Weather",
            "    AaaThing {}\n",
        );
        let b = patch(
            "bbb",
            0,
            PatchOp::InsertBefore,
            "// Weather",
            "    BbbThing {}\n",
        );
        let ab = compose(STOCK, &[a.clone(), b.clone()]).unwrap();
        let ba = compose(STOCK, &[b, a]).unwrap();
        assert_eq!(ab, ba, "compose must be order-independent");
        // aaa sorts before bbb → appears first.
        assert!(ab.find("AaaThing").unwrap() < ab.find("BbbThing").unwrap());
    }

    #[test]
    fn recompose_is_stable() {
        // Underscore owner: the id grammar uses underscores — the fence regex
        // MUST recognize them or recomposition duplicates blocks.
        let set = vec![patch(
            "mod_x",
            0,
            PatchOp::InsertAfter,
            "import QtQuick",
            "import extra\n",
        )];
        let once = compose(STOCK, &set).unwrap();
        let twice = recompose(&once, &set).unwrap();
        assert_eq!(once, twice);
        // Removing the module returns pristine bytes.
        assert_eq!(recompose(&once, &[]).unwrap(), STOCK);
    }

    #[test]
    fn anchor_failures() {
        let missing = patch(
            "m",
            0,
            PatchOp::InsertAfter,
            "does not exist anywhere",
            "x\n",
        );
        let err = compose(STOCK, &[missing]).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::ANCHOR);

        let two_loaders = format!("{STOCK}    // Weather\n");
        let ambiguous = patch("m", 0, PatchOp::InsertBefore, "// Weather", "x\n");
        let err = compose(&two_loaders, &[ambiguous]).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::ANCHOR);
    }

    #[test]
    fn anchor_never_matches_fenced_content() {
        // Module A inserts text containing what module B uses as an anchor.
        let a = patch(
            "aaa",
            0,
            PatchOp::InsertBefore,
            "// Weather",
            "    // SECRET UNIQUE MARKER LINE\n",
        );
        let composed = compose(STOCK, std::slice::from_ref(&a)).unwrap();
        let b = patch(
            "bbb",
            0,
            PatchOp::InsertAfter,
            "SECRET UNIQUE MARKER",
            "    Evil {}\n",
        );
        let err = recompose(&composed, &[a, b]).unwrap_err();
        assert_eq!(
            crate::exit::code_of(&err),
            crate::exit::ANCHOR,
            "anchor must only see stripped text"
        );
    }

    #[test]
    fn broken_fences_detected() {
        for broken in [
            "// >>> iimp x/0 v1.0.0 >>>\nno close\n",
            "line\n// <<< iimp x/0 <<<\n",
            "// >>> iimp x/0 v1.0.0 >>>\n// >>> iimp y/0 v1.0.0 >>>\n// <<< iimp y/0 <<<\n// <<< iimp x/0 <<<\n",
            "// >>> iimp x/0 v1.0.0 >>>\n// <<< iimp y/0 <<<\n",
        ] {
            assert!(strip(broken).is_err(), "should reject: {broken:?}");
        }
    }

    #[test]
    fn indentation_follows_anchor() {
        let set = vec![patch(
            "m",
            0,
            PatchOp::InsertAfter,
            "panelFamily",
            "    property bool x: true\n",
        )];
        let composed = compose(STOCK, &set).unwrap();
        assert!(
            composed.contains("    // >>> iimp m/0 v1.0.0 >>>\n"),
            "fence must adopt anchor indentation"
        );
    }

    #[test]
    fn no_trailing_newline_stock() {
        let stock_nonl = "a\nb"; // no trailing newline
        let set = vec![patch("m", 0, PatchOp::InsertAfter, "b", "c\n")];
        let composed = compose(stock_nonl, &set).unwrap();
        let (stripped, _) = strip(&composed).unwrap();
        // Identity holds modulo the newline the engine must add to terminate the anchor line.
        assert_eq!(stripped.trim_end_matches('\n'), stock_nonl);
    }
}
