//! Durable host generation selection and downgrade protection.

use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::exit::{self, bail};
use crate::hostpatch;
use crate::manifest::SUPPORTED_PROTOCOL_MAX;
use crate::patch::{self, PatchInstance};
use crate::paths;
use crate::registry::{self, Lock};

pub const HOST_GENERATION: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct StoredHostPatch {
    pub target: String,
    #[serde(default)]
    pub optional: bool,
    pub patch: PatchInstance,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct HostDescriptor {
    pub generation: u32,
    pub protocol_version: u32,
    pub content_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct BundleManifest {
    generation: u32,
    protocol_version: u32,
    content_id: String,
    module_host_sha256: String,
    modules_config_sha256: String,
    patches_sha256: String,
}

#[derive(Debug, Clone)]
pub struct HostBundle {
    pub descriptor: HostDescriptor,
    pub module_host_qml: Vec<u8>,
    pub modules_config_qml: Vec<u8>,
    pub patches: Vec<StoredHostPatch>,
}

pub struct MutationContext {
    _lock: Lock,
    host: HostBundle,
    activate_after_write: bool,
}

impl MutationContext {
    pub fn host(&self) -> &HostBundle {
        &self.host
    }

    pub fn activate_after_host_write(&self) -> Result<()> {
        if self.activate_after_write {
            activate(&self.host.descriptor)?;
        }
        Ok(())
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum MutationMode {
    Normal,
    Reapply,
}

pub fn candidate_bundle() -> HostBundle {
    build_bundle(
        HOST_GENERATION,
        SUPPORTED_PROTOCOL_MAX,
        include_bytes!("../assets/ModuleHost.qml").to_vec(),
        include_bytes!("../assets/ModulesConfig.qml").to_vec(),
        hostpatch::embedded_host_patches()
            .into_iter()
            .map(|(target, patch)| StoredHostPatch {
                target: target.to_string(),
                optional: target == hostpatch::VERTICAL_BAR_FILE,
                patch,
            })
            .collect(),
    )
}

fn build_bundle(
    generation: u32,
    protocol_version: u32,
    module_host_qml: Vec<u8>,
    modules_config_qml: Vec<u8>,
    mut patches: Vec<StoredHostPatch>,
) -> HostBundle {
    patches.sort_by(|a, b| {
        (&a.target, &a.patch.owner, a.patch.index).cmp(&(&b.target, &b.patch.owner, b.patch.index))
    });
    let canonical = serde_json::to_vec(&serde_json::json!({
        "generation": generation,
        "protocolVersion": protocol_version,
        "moduleHostQml": String::from_utf8_lossy(&module_host_qml),
        "modulesConfigQml": String::from_utf8_lossy(&modules_config_qml),
        "patches": patches,
    }))
    .expect("canonical host serialization");
    let content_id = sha256(&canonical);
    HostBundle {
        descriptor: HostDescriptor {
            generation,
            protocol_version,
            content_id,
        },
        module_host_qml,
        modules_config_qml,
        patches,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GenerationChoice {
    Installed,
    Same,
    Candidate,
}

fn compare_generations(
    candidate: &HostDescriptor,
    installed: &HostDescriptor,
) -> Result<GenerationChoice> {
    match candidate.generation.cmp(&installed.generation) {
        std::cmp::Ordering::Less => Ok(GenerationChoice::Installed),
        std::cmp::Ordering::Equal if candidate.content_id == installed.content_id => {
            Ok(GenerationChoice::Same)
        }
        std::cmp::Ordering::Equal => Err(bail(
            exit::STATE,
            format!(
                "host generation {} content collision (installed {}, candidate {})",
                installed.generation, installed.content_id, candidate.content_id
            ),
        )),
        std::cmp::Ordering::Greater => Ok(GenerationChoice::Candidate),
    }
}

pub fn mutation_preflight(mode: MutationMode) -> Result<MutationContext> {
    registry::install_legacy_fence()?;
    let lock = Lock::acquire()?;
    let candidate = candidate_bundle();

    let (host, activate_after_write) = match read_current()? {
        Some(installed) => {
            let installed_bundle = load_bundle(&installed)?;
            match compare_generations(&candidate.descriptor, &installed)? {
                GenerationChoice::Installed | GenerationChoice::Same => (installed_bundle, false),
                GenerationChoice::Candidate => {
                    persist_bundle(&candidate)?;
                    (candidate, true)
                }
            }
        }
        None => {
            let live = live_presence();
            if live == LivePresence::Absent || live_matches(&candidate)? {
                persist_bundle(&candidate)?;
                activate(&candidate.descriptor)?;
                (candidate, false)
            } else if mode == MutationMode::Reapply {
                persist_bundle(&candidate)?;
                (candidate, true)
            } else {
                return Err(bail(
                    exit::STATE,
                    "live host differs from this candidate but has no authoritative descriptor; run `iimod reapply` to explicitly restore it",
                ));
            }
        }
    };

    Ok(MutationContext {
        _lock: lock,
        host,
        activate_after_write,
    })
}

pub fn selected_for_read() -> Result<Option<HostBundle>> {
    read_current()?.map(|d| load_bundle(&d)).transpose()
}

pub fn selected_or_candidate() -> Result<HostBundle> {
    selected_for_read().map(|host| host.unwrap_or_else(candidate_bundle))
}

fn read_current() -> Result<Option<HostDescriptor>> {
    let path = paths::host_current_path();
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs::read(&path).with_context(|| format!("reading {}", path.display()))?;
    let descriptor: HostDescriptor = serde_json::from_slice(&bytes)
        .map_err(|e| bail(exit::STATE, format!("host descriptor corrupt: {e}")))?;
    validate_descriptor(&descriptor)?;
    Ok(Some(descriptor))
}

fn validate_protocol_version(version: u32, label: &str) -> Result<()> {
    if version > SUPPORTED_PROTOCOL_MAX {
        return Err(bail(
            exit::PROTOCOL,
            format!(
                "{label} protocolVersion {version} is newer than supported {SUPPORTED_PROTOCOL_MAX}; upgrade iimod"
            ),
        ));
    }
    Ok(())
}

fn validate_descriptor(descriptor: &HostDescriptor) -> Result<()> {
    validate_protocol_version(descriptor.protocol_version, "host descriptor")?;
    if descriptor.generation == 0
        || descriptor.protocol_version == 0
        || descriptor.content_id.len() != 64
        || !descriptor
            .content_id
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(bail(exit::STATE, "host descriptor fields are invalid"));
    }
    Ok(())
}

fn bundle_dir(descriptor: &HostDescriptor) -> PathBuf {
    paths::host_generations_dir().join(format!(
        "{}-{}",
        descriptor.generation, descriptor.content_id
    ))
}

fn persist_bundle(bundle: &HostBundle) -> Result<()> {
    let final_dir = bundle_dir(&bundle.descriptor);
    if final_dir.exists() {
        load_bundle(&bundle.descriptor)?;
        return Ok(());
    }
    fs::create_dir_all(paths::host_generations_dir())?;
    let tmp = paths::host_generations_dir().join(format!(
        ".tmp-{}-{}",
        bundle.descriptor.content_id,
        std::process::id()
    ));
    if tmp.exists() {
        fs::remove_dir_all(&tmp)?;
    }
    fs::create_dir_all(tmp.join("assets"))?;
    atomic_file(&tmp.join("assets/ModuleHost.qml"), &bundle.module_host_qml)?;
    atomic_file(
        &tmp.join("assets/ModulesConfig.qml"),
        &bundle.modules_config_qml,
    )?;
    let patches = serde_json::to_vec_pretty(&bundle.patches)?;
    atomic_file(
        &tmp.join("patches.json"),
        &[patches, b"\n".to_vec()].concat(),
    )?;
    let manifest = BundleManifest {
        generation: bundle.descriptor.generation,
        protocol_version: bundle.descriptor.protocol_version,
        content_id: bundle.descriptor.content_id.clone(),
        module_host_sha256: sha256(&bundle.module_host_qml),
        modules_config_sha256: sha256(&bundle.modules_config_qml),
        patches_sha256: sha256(&serde_json::to_vec(&bundle.patches)?),
    };
    let bytes = serde_json::to_vec_pretty(&manifest)?;
    atomic_file(
        &tmp.join("manifest.json"),
        &[bytes, b"\n".to_vec()].concat(),
    )?;
    sync_dir(&tmp)?;
    fs::rename(&tmp, &final_dir)?;
    sync_dir(&paths::host_generations_dir())?;
    Ok(())
}

fn load_bundle(descriptor: &HostDescriptor) -> Result<HostBundle> {
    load_bundle_from_dir(descriptor, &bundle_dir(descriptor))
}

fn load_bundle_from_dir(descriptor: &HostDescriptor, dir: &Path) -> Result<HostBundle> {
    let manifest: BundleManifest = read_json(&dir.join("manifest.json"), "host bundle manifest")?;
    validate_protocol_version(manifest.protocol_version, "host bundle manifest")?;
    if manifest.generation != descriptor.generation
        || manifest.protocol_version != descriptor.protocol_version
        || manifest.content_id != descriptor.content_id
    {
        return Err(bail(
            exit::STATE,
            "host bundle manifest disagrees with current descriptor",
        ));
    }
    let module_host_qml = read_required(&dir.join("assets/ModuleHost.qml"))?;
    let modules_config_qml = read_required(&dir.join("assets/ModulesConfig.qml"))?;
    let patches: Vec<StoredHostPatch> = read_json(&dir.join("patches.json"), "host patches")?;
    if sha256(&module_host_qml) != manifest.module_host_sha256
        || sha256(&modules_config_qml) != manifest.modules_config_sha256
        || sha256(&serde_json::to_vec(&patches)?) != manifest.patches_sha256
    {
        return Err(bail(exit::STATE, "host bundle integrity check failed"));
    }
    let rebuilt = build_bundle(
        manifest.generation,
        manifest.protocol_version,
        module_host_qml,
        modules_config_qml,
        patches,
    );
    if rebuilt.descriptor.content_id != descriptor.content_id {
        return Err(bail(
            exit::STATE,
            "host bundle canonical content id mismatch",
        ));
    }
    Ok(rebuilt)
}

fn activate(descriptor: &HostDescriptor) -> Result<()> {
    fs::create_dir_all(paths::host_state_dir())?;
    let bytes = serde_json::to_vec_pretty(descriptor)?;
    atomic_file(
        &paths::host_current_path(),
        &[bytes, b"\n".to_vec()].concat(),
    )?;
    sync_dir(&paths::host_state_dir())
}

fn atomic_file(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path.parent().expect("atomic file parent");
    fs::create_dir_all(parent)?;
    let tmp = parent.join(format!(
        ".{}.tmp-{}",
        path.file_name().unwrap().to_string_lossy(),
        std::process::id()
    ));
    let mut file = File::create(&tmp)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    fs::rename(tmp, path)?;
    sync_dir(parent)
}

fn sync_dir(path: &Path) -> Result<()> {
    File::open(path)?.sync_all()?;
    Ok(())
}

fn read_required(path: &Path) -> Result<Vec<u8>> {
    fs::read(path).map_err(|e| {
        bail(
            exit::STATE,
            format!("host bundle missing {}: {e}", path.display()),
        )
    })
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path, label: &str) -> Result<T> {
    let bytes = read_required(path)?;
    serde_json::from_slice(&bytes).map_err(|e| bail(exit::STATE, format!("{label} corrupt: {e}")))
}

fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum LivePresence {
    Absent,
    Present,
}

fn live_presence() -> LivePresence {
    let ii = paths::ii_root();
    let assets = paths::host_dir().join("ModuleHost.qml").exists()
        || paths::host_dir().join("ModulesConfig.qml").exists()
        || paths::host_sentinel().exists();
    let fences = [
        "shell.qml",
        "modules/common/Config.qml",
        "modules/ii/bar/BarContent.qml",
        "settings.qml",
        hostpatch::VERTICAL_BAR_FILE,
    ]
    .iter()
    .any(|rel| {
        fs::read_to_string(ii.join(rel))
            .ok()
            .is_some_and(|s| s.contains("// >>> iimp host/"))
    });
    if assets || fences {
        LivePresence::Present
    } else {
        LivePresence::Absent
    }
}

pub fn live_matches(bundle: &HostBundle) -> Result<bool> {
    if fs::read(paths::host_dir().join("ModuleHost.qml"))
        .ok()
        .as_deref()
        != Some(bundle.module_host_qml.as_slice())
        || fs::read(paths::host_dir().join("ModulesConfig.qml"))
            .ok()
            .as_deref()
            != Some(bundle.modules_config_qml.as_slice())
    {
        return Ok(false);
    }
    let sentinel = match hostpatch::read_sentinel() {
        Some(value) => value,
        None => return Ok(false),
    };
    if sentinel.host_version != hostpatch::HOST_VERSION
        || sentinel.protocol_version != bundle.descriptor.protocol_version
        || sentinel.host_generation != Some(bundle.descriptor.generation)
        || sentinel.content_id.as_deref() != Some(bundle.descriptor.content_id.as_str())
    {
        return Ok(false);
    }
    let mut expected = std::collections::BTreeMap::<String, Vec<(u32, String, String)>>::new();
    for stored in &bundle.patches {
        if !paths::ii_root().join(&stored.target).exists() && stored.optional {
            continue;
        }
        expected.entry(stored.target.clone()).or_default().push((
            stored.patch.index,
            stored.patch.version.clone(),
            normalized_content(&stored.patch.content),
        ));
    }
    for blocks in expected.values_mut() {
        blocks.sort();
    }

    let mut found = std::collections::BTreeMap::<String, Vec<(u32, String, String)>>::new();
    for entry in walkdir::WalkDir::new(paths::ii_root()) {
        let Ok(entry) = entry else { continue };
        if !entry.file_type().is_file() {
            continue;
        }
        let Ok(text) = fs::read_to_string(entry.path()) else {
            continue;
        };
        let (_, blocks) = match patch::strip(&text) {
            Ok(value) => value,
            Err(_) if text.contains("iimp host/") => return Ok(false),
            Err(_) => continue,
        };
        let mut host_blocks: Vec<(u32, String, String)> = blocks
            .into_iter()
            .filter(|block| block.owner == hostpatch::HOST_OWNER)
            .map(|block| {
                (
                    block.index,
                    block.version,
                    normalized_content(&block.content),
                )
            })
            .collect();
        if host_blocks.is_empty() {
            continue;
        }
        host_blocks.sort();
        let rel = entry
            .path()
            .strip_prefix(paths::ii_root())
            .unwrap()
            .to_string_lossy()
            .into_owned();
        found.insert(rel, host_blocks);
    }
    Ok(found == expected)
}

fn normalized_content(content: &str) -> String {
    if content.ends_with('\n') {
        content.to_string()
    } else {
        format!("{content}\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generation_selection_order_is_monotonic() {
        let candidate = candidate_bundle();
        assert!(candidate.descriptor.generation > 1);
        assert_eq!(candidate.descriptor.generation, HOST_GENERATION);
        assert_eq!(candidate.descriptor.content_id.len(), 64);
    }

    #[test]
    fn generation_compare_covers_all_branches_and_collision() {
        let installed = HostDescriptor {
            generation: 2,
            protocol_version: 1,
            content_id: "same".into(),
        };
        let descriptor = |generation, content_id: &str| HostDescriptor {
            generation,
            protocol_version: 1,
            content_id: content_id.into(),
        };
        assert_eq!(
            compare_generations(&descriptor(1, "old"), &installed).unwrap(),
            GenerationChoice::Installed
        );
        assert_eq!(
            compare_generations(&descriptor(2, "same"), &installed).unwrap(),
            GenerationChoice::Same
        );
        assert_eq!(
            compare_generations(&descriptor(3, "new"), &installed).unwrap(),
            GenerationChoice::Candidate
        );
        let err = compare_generations(&descriptor(2, "different"), &installed).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::STATE);
    }

    #[test]
    fn future_descriptor_and_bundle_manifest_protocols_are_exit_10() {
        let descriptor = HostDescriptor {
            generation: HOST_GENERATION,
            protocol_version: SUPPORTED_PROTOCOL_MAX + 1,
            content_id: "a".repeat(64),
        };
        let err = validate_descriptor(&descriptor).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROTOCOL);

        let manifest = BundleManifest {
            generation: HOST_GENERATION,
            protocol_version: SUPPORTED_PROTOCOL_MAX + 1,
            content_id: "b".repeat(64),
            module_host_sha256: "c".repeat(64),
            modules_config_sha256: "d".repeat(64),
            patches_sha256: "e".repeat(64),
        };
        let bytes = serde_json::to_vec(&manifest).unwrap();
        let decoded: BundleManifest = serde_json::from_slice(&bytes).unwrap();
        let err = validate_protocol_version(decoded.protocol_version, "host bundle manifest")
            .unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROTOCOL);
    }

    #[test]
    fn load_bundle_rejects_future_manifest_protocol() {
        let root =
            std::env::temp_dir().join(format!("iimp-host-future-manifest-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);

        let descriptor = HostDescriptor {
            generation: HOST_GENERATION,
            protocol_version: SUPPORTED_PROTOCOL_MAX,
            content_id: "f".repeat(64),
        };
        let dir = root.join("bundle");
        std::fs::create_dir_all(&dir).unwrap();
        let manifest = BundleManifest {
            generation: descriptor.generation,
            protocol_version: SUPPORTED_PROTOCOL_MAX + 1,
            content_id: descriptor.content_id.clone(),
            module_host_sha256: "0".repeat(64),
            modules_config_sha256: "0".repeat(64),
            patches_sha256: "0".repeat(64),
        };
        std::fs::write(
            dir.join("manifest.json"),
            serde_json::to_vec(&manifest).unwrap(),
        )
        .unwrap();
        let err = load_bundle_from_dir(&descriptor, &dir).unwrap_err();
        assert_eq!(crate::exit::code_of(&err), crate::exit::PROTOCOL);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn canonical_id_covers_target_and_patch_bytes() {
        let base = candidate_bundle();
        let mut changed = base.patches.clone();
        changed[0].target.push_str(".other");
        let other = build_bundle(
            base.descriptor.generation,
            base.descriptor.protocol_version,
            base.module_host_qml.clone(),
            base.modules_config_qml.clone(),
            changed,
        );
        assert_ne!(base.descriptor.content_id, other.descriptor.content_id);
    }
}
