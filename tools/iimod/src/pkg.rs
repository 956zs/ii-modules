//! .iimod package format: tar.gz with a single `<id>/` top-level dir plus a
//! top-level `integrity.json` (SPEC 1.0 §3, §8.1). Extraction is sanitized.

use std::collections::BTreeMap;
use std::io::Read;
use std::path::{Component, Path, PathBuf};

use anyhow::{Context, Result};
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use serde::{Deserialize, Serialize};

use crate::exit::{self, bail};
use crate::store;

pub const DEFAULT_MAX_UNPACKED: u64 = 20 * 1024 * 1024;

// No deny_unknown_fields: integrity.json is tool-to-tool data and future
// tools may add optional fields (as `origin` was) — consumers must tolerate
// unknowns so old packages and new tools stay mutually compatible.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Integrity {
    pub spec_version: u32,
    pub manifest_sha256: String,
    pub files: BTreeMap<String, String>,
    /// Update index URL embedded at pack time (`iimod pack --origin`): the
    /// publisher's canonical source, so a hand-copied .iimod still knows
    /// where its updates live.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<String>,
}

/// Build `<id>.iimod` from a payload directory. Returns the integrity data.
pub fn pack(payload: &Path, id: &str, out_path: &Path, origin: Option<&str>) -> Result<Integrity> {
    let files = store::hash_tree(payload)?;
    let manifest_sha = files
        .get("module.json")
        .cloned()
        .ok_or_else(|| bail(exit::VALIDATION, "payload has no module.json"))?;
    let integrity = Integrity {
        spec_version: 1,
        manifest_sha256: manifest_sha,
        files: files.clone(),
        origin: origin.map(str::to_string),
    };

    let file = std::fs::File::create(out_path)
        .with_context(|| format!("creating {}", out_path.display()))?;
    let enc = GzEncoder::new(file, Compression::default());
    let mut tar = tar::Builder::new(enc);
    tar.mode(tar::HeaderMode::Deterministic);

    for rel in files.keys() {
        let disk = payload.join(rel);
        let mut f = std::fs::File::open(&disk)?;
        tar.append_file(format!("{id}/{rel}"), &mut f)?;
    }
    let integrity_bytes = serde_json::to_vec_pretty(&integrity)?;
    let mut header = tar::Header::new_gnu();
    header.set_size(integrity_bytes.len() as u64);
    header.set_mode(0o644);
    header.set_cksum();
    tar.append_data(&mut header, "integrity.json", integrity_bytes.as_slice())?;
    tar.into_inner()?.finish()?;
    Ok(integrity)
}

fn sanitized_rel(path: &Path) -> Result<PathBuf> {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::Normal(part) => {
                let s = part
                    .to_str()
                    .ok_or_else(|| bail(exit::VALIDATION, "package: non-UTF-8 entry name"))?;
                out.push(s);
            }
            Component::CurDir => {}
            _ => {
                return Err(bail(
                    exit::VALIDATION,
                    format!("package: unsafe path {:?}", path),
                ))
            }
        }
    }
    if out.as_os_str().is_empty() {
        return Err(bail(exit::VALIDATION, "package: empty entry name"));
    }
    Ok(out)
}

#[derive(Debug)]
#[allow(dead_code)] // id/integrity consumed by tests + future `info --pkg`
pub struct Unpacked {
    /// Directory containing the payload (== extracted `<id>/` dir).
    pub payload: PathBuf,
    pub id: String,
    pub integrity: Integrity,
}

/// Extract and fully verify a .iimod archive into `dest_parent` (a fresh temp dir).
pub fn unpack(archive: &Path, dest_parent: &Path, max_unpacked: u64) -> Result<Unpacked> {
    std::fs::create_dir_all(dest_parent)?;
    let file =
        std::fs::File::open(archive).with_context(|| format!("opening {}", archive.display()))?;
    let mut tar = tar::Archive::new(GzDecoder::new(file));

    let mut total: u64 = 0;
    let mut top: Option<String> = None;
    let mut integrity: Option<Integrity> = None;

    for entry in tar.entries()? {
        let mut entry = entry?;
        let header_type = entry.header().entry_type();
        match header_type {
            tar::EntryType::Regular => {}
            tar::EntryType::Directory => continue,
            other => {
                return Err(bail(
                    exit::VALIDATION,
                    format!(
                        "package: entry type {:?} not allowed (symlinks/special files rejected)",
                        other
                    ),
                ))
            }
        }
        if entry.header().mode().unwrap_or(0) & 0o4000 != 0 {
            return Err(bail(exit::VALIDATION, "package: setuid bit rejected"));
        }
        let raw_path = entry.path()?.into_owned();
        let rel = sanitized_rel(&raw_path)?;

        total += entry.size();
        if total > max_unpacked {
            return Err(bail(
                exit::VALIDATION,
                format!("package exceeds {max_unpacked} bytes unpacked (override with --max-size)"),
            ));
        }

        let mut bytes = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut bytes)?;

        if rel == Path::new("integrity.json") {
            integrity = Some(
                serde_json::from_slice(&bytes)
                    .map_err(|e| bail(exit::INTEGRITY, format!("integrity.json: {e}")))?,
            );
            continue;
        }

        let mut comps = rel.components();
        let first = comps
            .next()
            .and_then(|c| c.as_os_str().to_str())
            .ok_or_else(|| bail(exit::VALIDATION, "package: entry outside a top-level dir"))?
            .to_string();
        match &top {
            None => top = Some(first.clone()),
            Some(t) if *t == first => {}
            Some(t) => {
                return Err(bail(
                    exit::VALIDATION,
                    format!("package: multiple top-level dirs ({t:?} and {first:?})"),
                ))
            }
        }

        let dest = dest_parent.join(&rel);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&dest, &bytes)?;
    }

    let id = top.ok_or_else(|| bail(exit::VALIDATION, "package: no payload entries"))?;
    let integrity =
        integrity.ok_or_else(|| bail(exit::INTEGRITY, "package: integrity.json missing"))?;
    let payload = dest_parent.join(&id);

    // Full integrity verification: exact file set + hashes.
    let actual = store::hash_tree(&payload)?;
    if actual != integrity.files {
        let expected: Vec<_> = integrity.files.keys().collect();
        let got: Vec<_> = actual.keys().collect();
        return Err(bail(
            exit::INTEGRITY,
            format!("package integrity mismatch (expected {expected:?}, got {got:?} or hash diff)"),
        ));
    }
    match actual.get("module.json") {
        Some(h) if *h == integrity.manifest_sha256 => {}
        _ => return Err(bail(exit::INTEGRITY, "package: manifest hash mismatch")),
    }

    Ok(Unpacked {
        payload,
        id,
        integrity,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("iimp-pkg-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn make_payload(dir: &Path) -> PathBuf {
        let payload = dir.join("hello_bar");
        std::fs::create_dir_all(payload.join("translations")).unwrap();
        std::fs::write(
            payload.join("module.json"),
            include_str!("../../../spec/fixtures/valid/tier-a-minimal.json"),
        )
        .unwrap();
        std::fs::write(payload.join("bar.qml"), "Item {}\n").unwrap();
        std::fs::write(payload.join("translations/zh_TW.json"), "{}\n").unwrap();
        payload
    }

    #[test]
    fn pack_unpack_roundtrip() {
        let dir = base("roundtrip");
        let payload = make_payload(&dir);
        let archive = dir.join("hello_bar.iimod");
        pack(
            &payload,
            "hello_bar",
            &archive,
            Some("https://example.com/mods/index.json"),
        )
        .unwrap();

        let out = dir.join("extract");
        let unpacked = unpack(&archive, &out, DEFAULT_MAX_UNPACKED).unwrap();
        assert_eq!(unpacked.id, "hello_bar");
        assert_eq!(
            unpacked.integrity.origin.as_deref(),
            Some("https://example.com/mods/index.json")
        );
        assert_eq!(
            store::hash_tree(&payload).unwrap(),
            store::hash_tree(&unpacked.payload).unwrap()
        );
    }

    #[test]
    fn tampered_content_fails_integrity() {
        let dir = base("tamper");
        let payload = make_payload(&dir);
        let archive = dir.join("x.iimod");
        pack(&payload, "hello_bar", &archive, None).unwrap();

        // Repack with mutated file but original integrity.json.
        let out = dir.join("mutate");
        let unpacked = unpack(&archive, &out, DEFAULT_MAX_UNPACKED).unwrap();
        std::fs::write(unpacked.payload.join("bar.qml"), "Item { Evil {} }\n").unwrap();
        let evil = dir.join("evil.iimod");
        {
            let f = std::fs::File::create(&evil).unwrap();
            let enc = GzEncoder::new(f, Compression::default());
            let mut tar = tar::Builder::new(enc);
            tar.append_dir_all("hello_bar", &unpacked.payload).unwrap();
            let ij = serde_json::to_vec(&unpacked.integrity).unwrap();
            let mut header = tar::Header::new_gnu();
            header.set_size(ij.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, "integrity.json", ij.as_slice())
                .unwrap();
            tar.into_inner().unwrap().finish().unwrap();
        }
        let err = unpack(&evil, &dir.join("evil-out"), DEFAULT_MAX_UNPACKED).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::INTEGRITY);
    }

    /// Writes header name bytes RAW (bypassing the tar crate's write-side path
    /// validation) — models a hand-crafted malicious archive.
    fn raw_archive(dir: &Path, entries: &[(&str, &[u8])]) -> PathBuf {
        let archive = dir.join("raw.iimod");
        let f = std::fs::File::create(&archive).unwrap();
        let enc = GzEncoder::new(f, Compression::default());
        let mut tar = tar::Builder::new(enc);
        for (name, bytes) in entries {
            let mut header = tar::Header::new_gnu();
            {
                let gnu = header.as_gnu_mut().expect("gnu header");
                let raw = name.as_bytes();
                assert!(raw.len() < gnu.name.len(), "test name too long");
                gnu.name[..raw.len()].copy_from_slice(raw);
            }
            header.set_size(bytes.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append(&header, *bytes).unwrap();
        }
        tar.into_inner().unwrap().finish().unwrap();
        archive
    }

    #[test]
    fn traversal_and_absolute_rejected() {
        let dir = base("traversal");
        let archive = raw_archive(&dir, &[("mod/../../etc/passwd", b"boom")]);
        let err = unpack(&archive, &dir.join("out"), DEFAULT_MAX_UNPACKED).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::VALIDATION);
    }

    #[test]
    fn symlink_rejected() {
        let dir = base("symlink");
        let archive = dir.join("sym.iimod");
        {
            let f = std::fs::File::create(&archive).unwrap();
            let enc = GzEncoder::new(f, Compression::default());
            let mut tar = tar::Builder::new(enc);
            let mut header = tar::Header::new_gnu();
            header.set_entry_type(tar::EntryType::Symlink);
            header.set_size(0);
            header.set_cksum();
            tar.append_link(&mut header, "hello_bar/evil", "/etc/passwd")
                .unwrap();
            tar.into_inner().unwrap().finish().unwrap();
        }
        let err = unpack(&archive, &dir.join("out"), DEFAULT_MAX_UNPACKED).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::VALIDATION);
    }

    #[test]
    fn oversize_rejected() {
        let dir = base("oversize");
        let big = vec![0u8; 4096];
        let archive = raw_archive(&dir, &[("hello_bar/big.bin", big.as_slice())]);
        let err = unpack(&archive, &dir.join("out"), 1024).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::VALIDATION);
    }

    #[test]
    fn multiple_top_dirs_rejected() {
        let dir = base("multitop");
        let archive = raw_archive(&dir, &[("aaa/x", b"1"), ("bbb/y", b"2")]);
        let err = unpack(&archive, &dir.join("out"), DEFAULT_MAX_UNPACKED).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::VALIDATION);
    }
}
