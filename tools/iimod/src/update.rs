//! `iimod update`: federated module updates.
//!
//! Every module may record an `origin` — the URL of a static index.json —
//! at install time (`iimod install --origin <url>`). Update walks the
//! registry, fetches each distinct origin once, compares semver, downloads
//! newer packages, verifies their sha256 against the index, and hands them
//! to the ordinary transactional install pipeline. No daemon, no central
//! repository, no protocol change: origins live in the registry (schema v2),
//! manifests are untouched.
//!
//! Transport is the system `curl` (declared project dependency of this tool,
//! universal on the target distro). https:// and file:// only — file origins
//! exist for LAN shares and offline tests.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

use crate::exit::{self, bail};
use crate::install::{self, InstallOpts};
use crate::registry;
use crate::store;

const INDEX_MAX_BYTES: u64 = 1024 * 1024; // an index is small; 1 MiB is generous
const CURL_TIMEOUT_SECS: u32 = 60;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Index {
    index_version: u32,
    modules: BTreeMap<String, IndexEntry>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct IndexEntry {
    version: String,
    /// Absolute, or relative to the index URL's directory.
    url: String,
    sha256: String,
}

fn check_url_scheme(url: &str) -> Result<()> {
    if url.starts_with("https://") || url.starts_with("file://") {
        Ok(())
    } else {
        Err(bail(
            exit::USAGE,
            format!("origin {url:?}: only https:// and file:// URLs are supported"),
        ))
    }
}

/// Resolve a possibly-relative package URL against the index URL's directory.
fn resolve_url(index_url: &str, url: &str) -> String {
    if url.starts_with("https://") || url.starts_with("file://") {
        return url.to_string();
    }
    match index_url.rfind('/') {
        Some(i) => format!("{}/{}", &index_url[..i], url),
        None => url.to_string(),
    }
}

pub(crate) fn curl_fetch(url: &str, out: &Path, max_bytes: u64) -> Result<()> {
    check_url_scheme(url)?;
    let status = std::process::Command::new("curl")
        .args([
            "--fail",
            "--silent",
            "--show-error",
            "--location",
            "--proto",
            "=https,file",
            "--max-time",
            &CURL_TIMEOUT_SECS.to_string(),
            "--max-filesize",
            &max_bytes.to_string(),
            "--output",
        ])
        .arg(out)
        .arg(url)
        .status()
        .context("running curl (is curl installed?)")?;
    if !status.success() {
        return Err(bail(
            exit::INTERNAL,
            format!("curl failed for {url} (exit {:?})", status.code()),
        ));
    }
    let len = std::fs::metadata(out).map(|m| m.len()).unwrap_or(0);
    if len == 0 || len > max_bytes {
        return Err(bail(
            exit::INTERNAL,
            format!("fetched {url}: implausible size {len} bytes"),
        ));
    }
    Ok(())
}

fn fetch_index(origin: &str, tmp: &Path) -> Result<Index> {
    let file = tmp.join("index.json");
    curl_fetch(origin, &file, INDEX_MAX_BYTES)?;
    let bytes = std::fs::read(&file)?;
    let index: Index = serde_json::from_slice(&bytes)
        .map_err(|e| bail(exit::VALIDATION, format!("origin {origin}: bad index: {e}")))?;
    if index.index_version != 1 {
        return Err(bail(
            exit::VALIDATION,
            format!(
                "origin {origin}: indexVersion {} unsupported (this build supports 1)",
                index.index_version
            ),
        ));
    }
    Ok(index)
}

struct Candidate {
    id: String,
    installed: semver::Version,
    available: semver::Version,
    package_url: String,
    sha256: String,
    tier_b: bool,
}

pub fn cmd_update(
    id: Option<&str>,
    allow_patches: bool,
    dry_run: bool,
    max_size: u64,
) -> Result<()> {
    let reg = registry::load()?;

    let targets: Vec<_> = reg
        .modules
        .iter()
        .filter(|m| id.is_none_or(|want| m.manifest.id == want))
        .collect();
    if let Some(want) = id {
        if targets.is_empty() {
            return Err(bail(exit::USAGE, format!("no such module: {want}")));
        }
        if targets.iter().all(|m| m.origin.is_none()) {
            return Err(bail(
                exit::USAGE,
                format!("{want} has no recorded origin; reinstall with --origin <index-url>"),
            ));
        }
    }

    let tmp = tmpdir()?;
    let mut indexes: BTreeMap<String, Index> = BTreeMap::new();
    let mut candidates: Vec<Candidate> = Vec::new();
    let mut skipped_no_origin = 0u32;

    for m in &targets {
        let Some(origin) = &m.origin else {
            skipped_no_origin += 1;
            continue;
        };
        if !indexes.contains_key(origin) {
            indexes.insert(origin.clone(), fetch_index(origin, &tmp)?);
        }
        let index = &indexes[origin];
        let Some(entry) = index.modules.get(&m.manifest.id) else {
            eprintln!("• {}: not listed by its origin, skipping", m.manifest.id);
            continue;
        };
        let installed = m.manifest.semver()?;
        let available = semver::Version::parse(&entry.version).map_err(|e| {
            bail(
                exit::VALIDATION,
                format!("origin lists bad version for {}: {e}", m.manifest.id),
            )
        })?;
        if available > installed {
            candidates.push(Candidate {
                id: m.manifest.id.clone(),
                installed,
                available,
                package_url: resolve_url(origin, &entry.url),
                sha256: entry.sha256.to_lowercase(),
                tier_b: m.manifest.is_tier_b(),
            });
        }
    }

    if candidates.is_empty() {
        println!(
            "✓ everything up to date{}",
            if skipped_no_origin > 0 {
                format!(" ({skipped_no_origin} module(s) without origin not checked)")
            } else {
                String::new()
            }
        );
        return Ok(());
    }

    for c in &candidates {
        println!(
            "{} {} → {}{}",
            c.id,
            c.installed,
            c.available,
            if c.tier_b { "  [Tier B]" } else { "" }
        );
    }
    if dry_run {
        return Ok(());
    }
    if let Some(blocked) = candidates.iter().find(|c| c.tier_b && !allow_patches) {
        return Err(bail(
            exit::NEEDS_ALLOW_PATCHES,
            format!(
                "{} is a Tier B update: its patches may have changed.\nReview the new version, then re-run with --allow-patches",
                blocked.id
            ),
        ));
    }

    for c in &candidates {
        let pkg_path = tmp.join(format!("{}-{}.iimod", c.id, c.available));
        curl_fetch(&c.package_url, &pkg_path, max_size)?;
        let digest = store::sha256_file(&pkg_path)?;
        if digest != c.sha256 {
            return Err(bail(
                exit::INTEGRITY,
                format!(
                    "{}: package sha256 mismatch\n  index: {}\n  got:   {}",
                    c.id, c.sha256, digest
                ),
            ));
        }
        install::cmd_install(
            &pkg_path,
            &InstallOpts {
                allow_patches,
                reinstall: false,
                no_enable: false,
                max_size,
                origin: None, // preserve the recorded origin
                derived_origin: None,
            },
        )?;
    }
    println!("✓ updated {} module(s)", candidates.len());
    Ok(())
}

fn tmpdir() -> Result<PathBuf> {
    let dir = crate::paths::tmp_dir().join(format!(
        "update-{}-{}",
        registry::now_epoch(),
        std::process::id()
    ));
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}
