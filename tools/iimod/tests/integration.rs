//! Integration tests: run the built iimod binary against a miniature fake ii
//! tree with isolated env roots. IIMOD_NO_QS=1 guarantees no IPC ever reaches
//! a real session.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Output;

fn bin() -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_BIN_EXE_iimod"));
    assert!(p.exists(), "binary missing: {}", p.display());
    p = p.canonicalize().unwrap();
    p
}

struct World {
    root: PathBuf,
}

/// Write the miniature stock tree (real anchor lines) at `ii`.
fn write_stock_tree(ii: &Path) {
    std::fs::create_dir_all(ii.join("modules/common")).unwrap();
    std::fs::create_dir_all(ii.join("modules/ii/bar")).unwrap();
    std::fs::create_dir_all(ii.join("services")).unwrap();
    std::fs::write(
        ii.join("shell.qml"),
        "import \"panelFamilies\"\n\nShellRoot {\n    ReloadPopup {}\n}\n",
    )
    .unwrap();
    std::fs::write(
        ii.join("modules/common/Config.qml"),
        "Singleton {\n    JsonAdapter {\n            property string panelFamily: \"ii\"\n    }\n}\n",
    )
    .unwrap();
    std::fs::write(
        ii.join("modules/ii/bar/BarContent.qml"),
        "Item {\n    RowLayout {\n            // Weather\n            Loader {}\n    }\n}\n",
    )
    .unwrap();
    std::fs::write(
        ii.join("settings.qml"),
        "Item {\n    property var pages: [\n        { name: \"Quick\" }\n    ]\n}\n",
    )
    .unwrap();
    std::fs::write(ii.join("modules/ii/bar/BarGroup.qml"), "Item {}\n").unwrap();
    std::fs::write(
        ii.join("modules/common/Extra.qml"),
        "Item { // ExtraAnchor\n}\n",
    )
    .unwrap();
    std::fs::create_dir_all(ii.join("modules/ii/verticalBar")).unwrap();
    std::fs::write(
        ii.join("modules/ii/verticalBar/VerticalBarContent.qml"),
        "Item {\n    ColumnLayout {\n            spacing: 10\n    }\n    ColumnLayout {\n            Bar.SysTray {\n            }\n    }\n}\n",
    )
    .unwrap();
    std::fs::write(
        ii.join("services/Network.qml"),
        "Singleton { property string materialSymbol: \"lan\" }\n",
    )
    .unwrap();
}

impl World {
    fn new(name: &str) -> World {
        let root = std::env::temp_dir().join(format!("iimp-it-{}-{}", std::process::id(), name));
        let _ = std::fs::remove_dir_all(&root);
        write_stock_tree(&root.join("ii"));
        World { root }
    }

    fn ii(&self) -> PathBuf {
        self.root.join("ii")
    }

    fn run(&self, args: &[&str]) -> Output {
        std::process::Command::new(bin())
            .args(args)
            .env("IIMOD_II_ROOT", self.ii())
            .env("IIMOD_STATE_ROOT", self.root.join("state"))
            .env("IIMOD_SHELLCONFIG_ROOT", self.root.join("shellconfig"))
            .env("IIMOD_NO_QS", "1")
            .output()
            .expect("spawn iimod")
    }

    fn expect(&self, args: &[&str], code: i32) -> Output {
        let out = self.run(args);
        assert_eq!(
            out.status.code(),
            Some(code),
            "args={args:?}\nstdout: {}\nstderr: {}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        out
    }

    fn hash_ii(&self) -> BTreeMap<String, String> {
        hash_tree(&self.ii())
    }

    fn make_module(&self, id: &str, manifest_extra: serde_json::Value) -> PathBuf {
        let payload = self.root.join("src").join(id);
        std::fs::create_dir_all(payload.join("translations")).unwrap();
        let mut manifest = serde_json::json!({
            "protocolVersion": 1,
            "id": id,
            "name": {"en_US": id, "zh_TW": format!("{id} 中文")},
            "description": {"en_US": "test module"},
            "version": "1.0.0",
            "authors": ["it"],
            "license": "MIT",
            "slots": ["bar"],
            "compat": {"probes": [
                {"type": "file-exists", "path": "modules/ii/bar/BarGroup.qml", "reason": "bar container"}
            ]},
            "capabilities": []
        });
        merge_json(&mut manifest, manifest_extra);
        std::fs::write(
            payload.join("module.json"),
            serde_json::to_string_pretty(&manifest).unwrap(),
        )
        .unwrap();
        std::fs::write(payload.join("bar.qml"), "Item { }\n").unwrap();
        std::fs::write(
            payload.join("translations/zh_TW.json"),
            format!("{{\"{id} greeting\": \"你好\"}}\n"),
        )
        .unwrap();
        payload
    }
}

fn merge_json(base: &mut serde_json::Value, extra: serde_json::Value) {
    if let (Some(b), serde_json::Value::Object(e)) = (base.as_object_mut(), extra) {
        for (k, v) in e {
            b.insert(k, v);
        }
    }
}

fn hash_tree(root: &Path) -> BTreeMap<String, String> {
    use sha2::{Digest, Sha256};
    let mut map = BTreeMap::new();
    fn walk(dir: &Path, root: &Path, map: &mut BTreeMap<String, String>) {
        for entry in std::fs::read_dir(dir).unwrap().flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, root, map);
            } else {
                let rel = path
                    .strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned();
                let mut hasher = Sha256::new();
                hasher.update(std::fs::read(&path).unwrap());
                map.insert(rel, format!("{:x}", hasher.finalize()));
            }
        }
    }
    walk(root, root, &mut map);
    map
}

fn sha256_bytes(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    format!("{:x}", Sha256::digest(bytes))
}

fn rewrite_current_bundle(w: &World, generation: u64, protocol: u64) {
    let state_host = w.root.join("state/host");
    let current: serde_json::Value =
        serde_json::from_slice(&std::fs::read(state_host.join("current.json")).unwrap()).unwrap();
    let old_dir = state_host.join("generations").join(format!(
        "{}-{}",
        current["generation"].as_u64().unwrap(),
        current["contentId"].as_str().unwrap()
    ));
    let module_host = std::fs::read(old_dir.join("assets/ModuleHost.qml")).unwrap();
    let modules_config = std::fs::read(old_dir.join("assets/ModulesConfig.qml")).unwrap();
    let patches: serde_json::Value =
        serde_json::from_slice(&std::fs::read(old_dir.join("patches.json")).unwrap()).unwrap();
    let canonical = serde_json::to_vec(&serde_json::json!({
        "generation": generation,
        "protocolVersion": protocol,
        "moduleHostQml": String::from_utf8_lossy(&module_host),
        "modulesConfigQml": String::from_utf8_lossy(&modules_config),
        "patches": patches,
    }))
    .unwrap();
    let content_id = sha256_bytes(&canonical);
    let dir = state_host
        .join("generations")
        .join(format!("{generation}-{content_id}"));
    std::fs::create_dir_all(dir.join("assets")).unwrap();
    std::fs::write(dir.join("assets/ModuleHost.qml"), &module_host).unwrap();
    std::fs::write(dir.join("assets/ModulesConfig.qml"), &modules_config).unwrap();
    let patch_bytes = serde_json::to_vec_pretty(&patches).unwrap();
    std::fs::write(
        dir.join("patches.json"),
        [patch_bytes, b"\n".to_vec()].concat(),
    )
    .unwrap();
    let manifest = serde_json::json!({
        "generation": generation,
        "protocolVersion": protocol,
        "contentId": content_id,
        "moduleHostSha256": sha256_bytes(&module_host),
        "modulesConfigSha256": sha256_bytes(&modules_config),
        "patchesSha256": sha256_bytes(&serde_json::to_vec(&patches).unwrap()),
    });
    std::fs::write(
        dir.join("manifest.json"),
        serde_json::to_string_pretty(&manifest).unwrap() + "\n",
    )
    .unwrap();
    std::fs::write(
        state_host.join("current.json"),
        serde_json::to_string_pretty(&serde_json::json!({
            "generation": generation,
            "protocolVersion": protocol,
            "contentId": content_id,
        }))
        .unwrap()
            + "\n",
    )
    .unwrap();
}

fn install_newer_host_bundle(w: &World) -> Vec<u8> {
    let state_host = w.root.join("state/host");
    let current_path = state_host.join("current.json");
    let current: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&current_path).unwrap()).unwrap();
    let old_dir = state_host.join("generations").join(format!(
        "{}-{}",
        current["generation"].as_u64().unwrap(),
        current["contentId"].as_str().unwrap()
    ));
    let module_host = std::fs::read(old_dir.join("assets/ModuleHost.qml")).unwrap();
    let mut modules_config = std::fs::read(old_dir.join("assets/ModulesConfig.qml")).unwrap();
    modules_config.extend_from_slice(b"\n// persisted generation 3\n");
    let patches: serde_json::Value =
        serde_json::from_slice(&std::fs::read(old_dir.join("patches.json")).unwrap()).unwrap();
    let generation = 3_u64;
    let protocol = current["protocolVersion"].as_u64().unwrap();
    let canonical = serde_json::to_vec(&serde_json::json!({
        "generation": generation,
        "protocolVersion": protocol,
        "moduleHostQml": String::from_utf8_lossy(&module_host),
        "modulesConfigQml": String::from_utf8_lossy(&modules_config),
        "patches": patches,
    }))
    .unwrap();
    let content_id = sha256_bytes(&canonical);
    let dir = state_host
        .join("generations")
        .join(format!("{generation}-{content_id}"));
    std::fs::create_dir_all(dir.join("assets")).unwrap();
    std::fs::write(dir.join("assets/ModuleHost.qml"), &module_host).unwrap();
    std::fs::write(dir.join("assets/ModulesConfig.qml"), &modules_config).unwrap();
    let patch_bytes = serde_json::to_vec_pretty(&patches).unwrap();
    std::fs::write(
        dir.join("patches.json"),
        [patch_bytes, b"\n".to_vec()].concat(),
    )
    .unwrap();
    let patch_canonical = serde_json::to_vec(&patches).unwrap();
    let manifest = serde_json::json!({
        "generation": generation,
        "protocolVersion": protocol,
        "contentId": content_id,
        "moduleHostSha256": sha256_bytes(&module_host),
        "modulesConfigSha256": sha256_bytes(&modules_config),
        "patchesSha256": sha256_bytes(&patch_canonical),
    });
    std::fs::write(
        dir.join("manifest.json"),
        serde_json::to_string_pretty(&manifest).unwrap() + "\n",
    )
    .unwrap();
    let descriptor = serde_json::json!({
        "generation": generation,
        "protocolVersion": protocol,
        "contentId": content_id,
    });
    std::fs::write(
        current_path,
        serde_json::to_string_pretty(&descriptor).unwrap() + "\n",
    )
    .unwrap();
    modules_config
}

/// Simulate the released mutator ordering: acquire `$STATE/lock`, then load and
/// write state/host bytes. The permanent PID-1 fence must stop it at step one.
fn simulate_released_host_writer(w: &World) -> bool {
    let lock_path = w.root.join("state/lock");
    let holder = std::fs::read_to_string(&lock_path).unwrap_or_default();
    let pid = holder.trim().parse::<u32>().ok();
    if pid.is_some_and(|pid| Path::new(&format!("/proc/{pid}")).exists()) {
        return false;
    }
    let _ = std::fs::remove_file(&lock_path);
    std::fs::write(
        w.ii().join("mod/iimp/ModulesConfig.qml"),
        "// stale embedded ModulesConfig.qml\n",
    )
    .unwrap();
    let registry_path = w.root.join("state/registry.json");
    let mut registry: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&registry_path).unwrap()).unwrap();
    registry["hostVersion"] = serde_json::Value::String("1.1.0".into());
    std::fs::write(
        registry_path,
        serde_json::to_string_pretty(&registry).unwrap() + "\n",
    )
    .unwrap();
    true
}

#[test]
fn legacy_pid1_fence_blocks_released_host_downgrade() {
    let w = World::new("host-downgrade");
    let first = w.make_module("current_host", serde_json::json!({}));
    w.expect(&["install", first.to_str().unwrap()], 0);

    let host_path = w.ii().join("mod/iimp/ModulesConfig.qml");
    let registry_path = w.root.join("state/registry.json");
    let descriptor_path = w.root.join("state/host/current.json");
    let host_before = std::fs::read(&host_path).unwrap();
    let registry_before = std::fs::read(&registry_path).unwrap();
    let descriptor_before = std::fs::read(&descriptor_path).unwrap();

    assert_eq!(std::fs::read(w.root.join("state/lock")).unwrap(), b"1\n");
    assert!(Path::new("/proc/1").exists(), "PID 1 must be live");
    assert!(!simulate_released_host_writer(&w));
    assert_eq!(std::fs::read(&host_path).unwrap(), host_before);
    assert_eq!(std::fs::read(&registry_path).unwrap(), registry_before);
    assert_eq!(std::fs::read(&descriptor_path).unwrap(), descriptor_before);
}

#[test]
fn first_migration_adopts_exact_live_host_and_rejects_unknown_live_host() {
    let matching = World::new("migration-match");
    let module = matching.make_module("migration_mod", serde_json::json!({}));
    matching.expect(&["install", module.to_str().unwrap()], 0);
    std::fs::remove_file(matching.root.join("state/host/current.json")).unwrap();
    matching.expect(&["disable", "migration_mod"], 0);
    assert!(matching.root.join("state/host/current.json").exists());

    let mismatch = World::new("migration-mismatch");
    let module = mismatch.make_module("mismatch_mod", serde_json::json!({}));
    mismatch.expect(&["install", module.to_str().unwrap()], 0);
    std::fs::remove_file(mismatch.root.join("state/host/current.json")).unwrap();
    std::fs::write(
        mismatch.ii().join("mod/iimp/ModulesConfig.qml"),
        "unknown live host\n",
    )
    .unwrap();
    let registry_before = std::fs::read(mismatch.root.join("state/registry.json")).unwrap();
    mismatch.expect(&["disable", "mismatch_mod"], 7);
    assert_eq!(
        std::fs::read(mismatch.root.join("state/registry.json")).unwrap(),
        registry_before
    );
    mismatch.expect(&["reapply"], 0);
    mismatch.expect(&["verify"], 0);
}

#[test]
fn first_migration_rejects_stale_fence_version_before_same_version_noop() {
    let w = World::new("migration-stale-version");
    let module = w.make_module("same_version_mod", serde_json::json!({}));
    w.expect(&["install", module.to_str().unwrap()], 0);
    let current_path = w.root.join("state/host/current.json");
    std::fs::remove_file(&current_path).unwrap();

    let sentinel_path = w.ii().join("mod/iimp/.iimp-host");
    let sentinel_before = std::fs::read(&sentinel_path).unwrap();
    let host_targets = [
        "shell.qml",
        "modules/common/Config.qml",
        "modules/ii/bar/BarContent.qml",
        "settings.qml",
        "modules/ii/verticalBar/VerticalBarContent.qml",
    ];
    let mut originals = Vec::new();
    let mut expected_headers = 0;
    let mut changed_headers = 0;
    for rel in host_targets {
        let path = w.ii().join(rel);
        if !path.exists() {
            continue;
        }
        let original = std::fs::read_to_string(&path).unwrap();
        let mut rewritten = String::with_capacity(original.len());
        for line in original.split_inclusive('\n') {
            if line.contains("// >>> iimp host/") {
                expected_headers += 1;
                let changed = line.replace(" v2 >>>", " v1 >>>");
                if changed != line {
                    changed_headers += 1;
                }
                rewritten.push_str(&changed);
            } else {
                rewritten.push_str(line);
            }
        }
        if rewritten != original {
            originals.push((path.clone(), original.into_bytes()));
            std::fs::write(path, rewritten).unwrap();
        }
    }
    assert!(
        expected_headers > 0,
        "fixture must contain host fence headers"
    );
    assert_eq!(
        changed_headers, expected_headers,
        "every host fence header must become stale"
    );
    assert_eq!(std::fs::read(&sentinel_path).unwrap(), sentinel_before);

    let out = w.expect(&["install", module.to_str().unwrap()], 7);
    assert!(!String::from_utf8_lossy(&out.stdout).contains("already installed"));
    assert!(!current_path.exists());
    assert_eq!(std::fs::read(&sentinel_path).unwrap(), sentinel_before);

    for (path, bytes) in originals {
        std::fs::write(path, bytes).unwrap();
    }
    let out = w.expect(&["install", module.to_str().unwrap()], 0);
    assert!(String::from_utf8_lossy(&out.stdout).contains("already installed"));
    assert!(current_path.exists());
    assert_eq!(std::fs::read(&sentinel_path).unwrap(), sentinel_before);
}

#[test]
fn newer_generation_future_protocol_is_exit_10_without_mutation() {
    let w = World::new("future-host-protocol");
    let first = w.make_module("protocol_first", serde_json::json!({}));
    w.expect(&["install", first.to_str().unwrap()], 0);
    rewrite_current_bundle(&w, 3, 2);

    let descriptor_path = w.root.join("state/host/current.json");
    let descriptor_before = std::fs::read(&descriptor_path).unwrap();
    let descriptor: serde_json::Value = serde_json::from_slice(&descriptor_before).unwrap();
    assert_eq!(descriptor["protocolVersion"], 2);
    let registry_before = std::fs::read(w.root.join("state/registry.json")).unwrap();
    let module_host_before = std::fs::read(w.ii().join("mod/iimp/ModuleHost.qml")).unwrap();
    let modules_config_before = std::fs::read(w.ii().join("mod/iimp/ModulesConfig.qml")).unwrap();

    let second = w.make_module("protocol_second", serde_json::json!({}));
    let out = w.expect(&["install", second.to_str().unwrap()], 10);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("protocolVersion") && stderr.contains("newer than supported"));
    assert_eq!(std::fs::read(&descriptor_path).unwrap(), descriptor_before);
    assert_eq!(
        std::fs::read(w.root.join("state/registry.json")).unwrap(),
        registry_before
    );
    assert_eq!(
        std::fs::read(w.ii().join("mod/iimp/ModuleHost.qml")).unwrap(),
        module_host_before
    );
    assert_eq!(
        std::fs::read(w.ii().join("mod/iimp/ModulesConfig.qml")).unwrap(),
        modules_config_before
    );
}

#[test]
fn newer_candidate_upgrades_older_descriptor() {
    let w = World::new("candidate-upgrade");
    let first = w.make_module("upgrade_first", serde_json::json!({}));
    w.expect(&["install", first.to_str().unwrap()], 0);
    rewrite_current_bundle(&w, 1, 1);
    let second = w.make_module("upgrade_second", serde_json::json!({}));
    w.expect(&["install", second.to_str().unwrap()], 0);
    let current: serde_json::Value =
        serde_json::from_slice(&std::fs::read(w.root.join("state/host/current.json")).unwrap())
            .unwrap();
    assert_eq!(current["generation"], 2);
    w.expect(&["verify"], 0);
}

#[test]
fn stale_guard_aware_candidate_preserves_newer_host_on_install_and_reapply() {
    let w = World::new("newer-host");
    let first = w.make_module("first_mod", serde_json::json!({}));
    w.expect(&["install", first.to_str().unwrap()], 0);
    let newer_asset = install_newer_host_bundle(&w);

    let second = w.make_module("second_mod", serde_json::json!({}));
    w.expect(&["install", second.to_str().unwrap()], 0);
    assert_eq!(
        std::fs::read(w.ii().join("mod/iimp/ModulesConfig.qml")).unwrap(),
        newer_asset
    );
    let descriptor: serde_json::Value =
        serde_json::from_slice(&std::fs::read(w.root.join("state/host/current.json")).unwrap())
            .unwrap();
    assert_eq!(descriptor["generation"], 3);

    std::fs::remove_dir_all(w.ii()).unwrap();
    write_stock_tree(&w.ii());
    w.expect(&["reapply"], 0);
    assert_eq!(
        std::fs::read(w.ii().join("mod/iimp/ModulesConfig.qml")).unwrap(),
        newer_asset
    );
    w.expect(&["verify"], 0);
}

#[test]
fn host_tampering_is_reported_for_bundle_assets_sentinel_imports_and_fences() {
    type TamperCase = (&'static str, Box<dyn Fn(&World)>);
    let cases: Vec<TamperCase> = vec![
        (
            "bundle",
            Box::new(|w| {
                let current: serde_json::Value = serde_json::from_slice(
                    &std::fs::read(w.root.join("state/host/current.json")).unwrap(),
                )
                .unwrap();
                let dir = w.root.join("state/host/generations").join(format!(
                    "{}-{}",
                    current["generation"].as_u64().unwrap(),
                    current["contentId"].as_str().unwrap()
                ));
                std::fs::write(dir.join("assets/ModuleHost.qml"), "tampered\n").unwrap();
            }),
        ),
        (
            "assets",
            Box::new(|w| {
                std::fs::write(w.ii().join("mod/iimp/ModulesConfig.qml"), "tampered\n").unwrap();
            }),
        ),
        (
            "sentinel",
            Box::new(|w| {
                std::fs::write(w.ii().join("mod/iimp/.iimp-host"), "{}\n").unwrap();
            }),
        ),
        (
            "imports",
            Box::new(|w| {
                std::fs::write(w.ii().join("mod/iimp/ModuleImports.qml"), "tampered\n").unwrap();
            }),
        ),
        (
            "fence",
            Box::new(|w| {
                let path = w.ii().join("shell.qml");
                let text = std::fs::read_to_string(&path).unwrap();
                std::fs::write(
                    path,
                    text.replace("ModuleHost {}", "ModuleHost { visible: false }"),
                )
                .unwrap();
            }),
        ),
    ];
    for (name, tamper) in cases {
        let w = World::new(&format!("tamper-{name}"));
        let module = w.make_module("tamper_mod", serde_json::json!({}));
        w.expect(&["install", module.to_str().unwrap()], 0);
        tamper(&w);
        w.expect(&["verify"], 7);
    }
}

#[test]
fn module_only_patch_target_survives_toggle_and_reapply() {
    let w = World::new("module-only-target");
    let payload = w.make_module(
        "extra_patcher",
        serde_json::json!({
            "patches": [{
                "file": "modules/common/Extra.qml",
                "op": "insert-after",
                "anchor": "Item { // ExtraAnchor",
                "content": "    property bool patched: true\n"
            }]
        }),
    );
    w.expect(
        &["install", payload.to_str().unwrap(), "--allow-patches"],
        0,
    );
    let target = w.ii().join("modules/common/Extra.qml");
    assert!(std::fs::read_to_string(&target)
        .unwrap()
        .contains("extra_patcher/0"));
    w.expect(&["disable", "extra_patcher"], 0);
    assert!(!std::fs::read_to_string(&target)
        .unwrap()
        .contains("extra_patcher/0"));
    w.expect(&["enable", "extra_patcher"], 0);
    std::fs::remove_dir_all(w.ii()).unwrap();
    write_stock_tree(&w.ii());
    w.expect(&["reapply"], 0);
    assert!(std::fs::read_to_string(&target)
        .unwrap()
        .contains("extra_patcher/0"));
    w.expect(&["verify"], 0);
}

#[test]
fn tier_a_install_uninstall_byte_clean() {
    let w = World::new("tier-a-clean");
    let pristine = w.hash_ii();
    let payload = w.make_module("hello_widget", serde_json::json!({}));

    w.expect(&["validate", payload.to_str().unwrap()], 0);
    w.expect(&["check", payload.to_str().unwrap()], 0);
    w.expect(&["install", payload.to_str().unwrap()], 0);

    // Host patches landed; module dir exists; projections written.
    let shell = std::fs::read_to_string(w.ii().join("shell.qml")).unwrap();
    assert!(shell.contains("import qs.mod.iimp") && shell.contains("ModuleHost {}"));
    assert!(w.ii().join("mod/hello_widget/bar.qml").exists());
    assert!(w.ii().join("mod/iimp/ModuleHost.qml").exists());
    assert!(w.ii().join("mod/iimp/ModulesConfig.qml").exists());
    let config = std::fs::read_to_string(w.root.join("shellconfig/config.json")).unwrap();
    assert!(config.contains("hello_widget"));
    let translations =
        std::fs::read_to_string(w.root.join("shellconfig/translations/zh_TW.json")).unwrap();
    assert!(translations.contains("你好"));
    w.expect(&["verify"], 0);

    // Uninstall → host stays (harmless), module gone, translations unmerged.
    w.expect(&["uninstall", "hello_widget"], 0);
    assert!(!w.ii().join("mod/hello_widget").exists());
    let translations =
        std::fs::read_to_string(w.root.join("shellconfig/translations/zh_TW.json")).unwrap();
    assert!(!translations.contains("你好"));

    // Byte-clean modulo the host (strip host = pristine): compare stripped stock files.
    for rel in [
        "shell.qml",
        "modules/common/Config.qml",
        "modules/ii/bar/BarContent.qml",
        "settings.qml",
    ] {
        let current = std::fs::read_to_string(w.ii().join(rel)).unwrap();
        let mut stripped = String::new();
        let mut in_fence = false;
        for line in current.split_inclusive('\n') {
            if line.contains(">>> iimp ") {
                in_fence = true;
                continue;
            }
            if line.contains("<<< iimp ") {
                in_fence = false;
                continue;
            }
            if !in_fence {
                stripped.push_str(line);
            }
        }
        let pristine_content_hash = pristine.get(rel).unwrap();
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(stripped.as_bytes());
        assert_eq!(
            &format!("{:x}", hasher.finalize()),
            pristine_content_hash,
            "{rel} not byte-clean after strip"
        );
    }
}

#[test]
fn tier_b_gate_and_anchor_determinism() {
    let w = World::new("tier-b");
    let tier_b = serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-before",
            "anchor": "            // Weather",
            "content": "            BbbThing {}\n"
        }],
    });
    let payload_b = w.make_module("bbb_patcher", tier_b);

    // Hard gate: exit 9 without --allow-patches.
    let out = w.expect(&["install", payload_b.to_str().unwrap()], 9);
    assert!(String::from_utf8_lossy(&out.stderr).contains("--allow-patches"));

    // Second Tier B module on the SAME anchor.
    let tier_a2 = serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-before",
            "anchor": "            // Weather",
            "content": "            AaaThing {}\n"
        }],
    });
    let payload_a = w.make_module("aaa_patcher", tier_a2);

    // Install order B then A.
    w.expect(
        &["install", payload_b.to_str().unwrap(), "--allow-patches"],
        0,
    );
    w.expect(
        &["install", payload_a.to_str().unwrap(), "--allow-patches"],
        0,
    );
    let bytes_ba = std::fs::read_to_string(w.ii().join("modules/ii/bar/BarContent.qml")).unwrap();

    // Fresh world, install order A then B → identical bytes (determinism law).
    let w2 = World::new("tier-b-order2");
    let payload_b2 = w2.make_module(
        "bbb_patcher",
        serde_json::json!({
            "patches": [{
                "file": "modules/ii/bar/BarContent.qml",
                "op": "insert-before",
                "anchor": "            // Weather",
                "content": "            BbbThing {}\n"
            }],
        }),
    );
    let payload_a2 = w2.make_module(
        "aaa_patcher",
        serde_json::json!({
            "patches": [{
                "file": "modules/ii/bar/BarContent.qml",
                "op": "insert-before",
                "anchor": "            // Weather",
                "content": "            AaaThing {}\n"
            }],
        }),
    );
    w2.expect(
        &["install", payload_a2.to_str().unwrap(), "--allow-patches"],
        0,
    );
    w2.expect(
        &["install", payload_b2.to_str().unwrap(), "--allow-patches"],
        0,
    );
    let bytes_ab = std::fs::read_to_string(w2.ii().join("modules/ii/bar/BarContent.qml")).unwrap();
    assert_eq!(bytes_ba, bytes_ab, "install order must not affect bytes");
    assert!(bytes_ab.find("AaaThing").unwrap() < bytes_ab.find("BbbThing").unwrap());

    // Bad anchor → exit 8 at check time.
    let bad = w.make_module(
        "bad_anchor",
        serde_json::json!({
            "patches": [{
                "file": "modules/ii/bar/BarContent.qml",
                "op": "insert-after",
                "anchor": "THIS ANCHOR EXISTS NOWHERE",
                "content": "            Nope {}\n"
            }],
        }),
    );
    w.expect(&["check", bad.to_str().unwrap()], 8);
}

#[test]
fn dependency_enforcement() {
    let w = World::new("deps");
    let dependent = w.make_module(
        "needs_core",
        serde_json::json!({
            "requires": {"modules": [{"id": "core_lib", "versionReq": ">=1.0, <2"}]}
        }),
    );
    // Missing dep → exit 5.
    w.expect(&["install", dependent.to_str().unwrap()], 5);

    let core = w.make_module("core_lib", serde_json::json!({}));
    w.expect(&["install", core.to_str().unwrap()], 0);
    w.expect(&["install", dependent.to_str().unwrap()], 0);

    // Uninstalling the dependency without cascade → exit 5; with cascade → both gone.
    w.expect(&["uninstall", "core_lib"], 5);
    w.expect(&["uninstall", "core_lib", "--cascade"], 0);
    assert!(!w.ii().join("mod/needs_core").exists());
    assert!(!w.ii().join("mod/core_lib").exists());
}

#[test]
fn wipe_and_reapply_restores_byte_identical() {
    let w = World::new("wipe");
    let payload = w.make_module(
        "survivor",
        serde_json::json!({
            "patches": [{
                "file": "modules/ii/bar/BarContent.qml",
                "op": "insert-before",
                "anchor": "            // Weather",
                "content": "            Survivor {}\n"
            }],
        }),
    );
    w.expect(
        &["install", payload.to_str().unwrap(), "--allow-patches"],
        0,
    );
    let installed_state = w.hash_ii();

    // Simulate a dots update: reset ONLY the ii tree to stock (state survives).
    std::fs::remove_dir_all(w.ii()).unwrap();
    write_stock_tree(&w.ii());
    assert!(!w.ii().join("mod").exists());

    // Detection + block.
    w.expect(&["verify"], 7);
    w.expect(
        &["install", w.root.join("src/survivor").to_str().unwrap()],
        7,
    );

    // Reapply → byte-identical to pre-wipe (modulo the host sentinel, whose
    // installedAtEpoch timestamp legitimately changes).
    w.expect(&["reapply"], 0);
    let strip_sentinel = |mut h: BTreeMap<String, String>| {
        h.remove("mod/iimp/.iimp-host");
        h
    };
    assert_eq!(
        strip_sentinel(w.hash_ii()),
        strip_sentinel(installed_state),
        "reapply must restore a byte-identical tree"
    );
    w.expect(&["verify"], 0);
}

#[test]
fn pack_install_roundtrip_and_tamper() {
    let w = World::new("pack");
    let payload = w.make_module("packed_mod", serde_json::json!({}));
    let out_pkg = w.root.join("packed_mod-1.0.0.iimod");
    w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            out_pkg.to_str().unwrap(),
            "--no-origin",
        ],
        0,
    );
    w.expect(&["install", out_pkg.to_str().unwrap()], 0);
    w.expect(&["uninstall", "packed_mod"], 0);

    // Tamper one byte inside the gzip → integrity/validation failure, not success.
    let mut bytes = std::fs::read(&out_pkg).unwrap();
    let len = bytes.len();
    bytes[len - 20] ^= 0xff;
    let bad_pkg = w.root.join("tampered.iimod");
    std::fs::write(&bad_pkg, bytes).unwrap();
    let out = w.run(&["install", bad_pkg.to_str().unwrap()]);
    assert_ne!(
        out.status.code(),
        Some(0),
        "tampered package must not install"
    );
}

#[test]
fn enable_disable_projection() {
    let w = World::new("toggle");
    let payload = w.make_module("toggle_me", serde_json::json!({}));
    w.expect(&["install", payload.to_str().unwrap()], 0);

    let config = || std::fs::read_to_string(w.root.join("shellconfig/config.json")).unwrap();
    assert!(config().contains("toggle_me"));
    w.expect(&["disable", "toggle_me"], 0);
    assert!(
        !config()
            .replace("\"enabledWindow\": []", "")
            .contains("toggle_me")
            || {
                let v: serde_json::Value = serde_json::from_str(&config()).unwrap();
                v["iimp"]["enabledBar"].as_array().unwrap().is_empty()
            }
    );
    w.expect(&["enable", "toggle_me"], 0);
    let v: serde_json::Value = serde_json::from_str(&config()).unwrap();
    assert_eq!(v["iimp"]["enabledBar"][0], "toggle_me");
}

#[test]
fn capability_lint_blocks_undeclared_exec() {
    let w = World::new("lint");
    let payload = w.make_module("sneaky", serde_json::json!({}));
    std::fs::write(
        payload.join("bar.qml"),
        "Item { Process { command: [\"curl\", \"evil\"] } }\n",
    )
    .unwrap();
    w.expect(&["validate", payload.to_str().unwrap()], 3);
    w.expect(&["install", payload.to_str().unwrap()], 3);
}

#[test]
fn update_from_file_origin() {
    let w = World::new("update");

    // v1.0.0 installed with a file:// origin pointing at a local repo dir.
    let payload = w.make_module("upd_widget", serde_json::json!({}));
    let repo = w.root.join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    let origin = format!("file://{}/index.json", repo.display());
    w.expect(
        &["install", payload.to_str().unwrap(), "--origin", &origin],
        0,
    );

    // Publish v1.1.0: bump the manifest, pack into the repo, index it.
    let manifest_path = payload.join("module.json");
    let manifest = std::fs::read_to_string(&manifest_path)
        .unwrap()
        .replace("\"1.0.0\"", "\"1.1.0\"");
    std::fs::write(&manifest_path, manifest).unwrap();
    let pkg_path = repo.join("upd_widget-1.1.0.iimod");
    w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            pkg_path.to_str().unwrap(),
            "--no-origin",
        ],
        0,
    );
    let sha = {
        use sha2::{Digest, Sha256};
        let mut h = Sha256::new();
        h.update(std::fs::read(&pkg_path).unwrap());
        format!("{:x}", h.finalize())
    };
    let write_index = |sha: &str| {
        std::fs::write(
            repo.join("index.json"),
            serde_json::json!({
                "indexVersion": 1,
                "modules": {
                    "upd_widget": {
                        "version": "1.1.0",
                        "url": "upd_widget-1.1.0.iimod", // relative to the index
                        "sha256": sha
                    }
                }
            })
            .to_string(),
        )
        .unwrap();
    };

    // Tampered index digest → integrity failure, nothing installed.
    write_index(&"0".repeat(64));
    w.expect(&["update"], 6);
    let out = w.expect(&["info", "upd_widget"], 0);
    assert!(String::from_utf8_lossy(&out.stdout).contains("1.0.0"));

    // Honest index: dry-run reports, update installs, origin survives.
    write_index(&sha);
    let out = w.expect(&["update", "--dry-run"], 0);
    assert!(String::from_utf8_lossy(&out.stdout).contains("1.0.0 → 1.1.0"));
    w.expect(&["update"], 0);
    let out = w.expect(&["info", "upd_widget"], 0);
    let info = String::from_utf8_lossy(&out.stdout);
    assert!(info.contains("1.1.0"), "info: {info}");
    let out = w.expect(&["update"], 0);
    assert!(String::from_utf8_lossy(&out.stdout).contains("up to date"));
}

#[test]
fn disable_removes_tier_b_patches() {
    let w = World::new("disflip");
    let tier_b = serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-before",
            "anchor": "            // Weather",
            "content": "            Flip {}\n"
        }]
    });
    let payload = w.make_module("flip_patcher", tier_b);
    w.expect(
        &["install", payload.to_str().unwrap(), "--allow-patches"],
        0,
    );
    let target = w.ii().join("modules/ii/bar/BarContent.qml");
    let read = || std::fs::read_to_string(&target).unwrap();
    assert!(
        read().contains("iimp flip_patcher/0"),
        "installed: fences present"
    );

    // Disabled -> the module's effects stop: fences gone, stock text back.
    w.expect(&["disable", "flip_patcher"], 0);
    assert!(!read().contains("flip_patcher"), "disabled: fences removed");
    assert!(read().contains("// Weather"), "stock text intact");

    // Enabled -> patches recomposed.
    w.expect(&["enable", "flip_patcher"], 0);
    assert!(
        read().contains("iimp flip_patcher/0"),
        "re-enabled: fences back"
    );
}

#[test]
fn url_install_auto_records_sibling_origin() {
    let w = World::new("urlinst");

    // Publish v1.0.0 into a local repo and install straight from the URL.
    let payload = w.make_module("url_widget", serde_json::json!({}));
    let repo = w.root.join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    let pkg = repo.join("url_widget-1.0.0.iimod");
    w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            pkg.to_str().unwrap(),
            "--no-origin",
        ],
        0,
    );
    let url = format!("file://{}", pkg.display());
    let out = w.expect(&["install", &url], 0);
    assert!(
        String::from_utf8_lossy(&out.stdout).contains("update origin:"),
        "auto-origin message"
    );
    let out = w.expect(&["info", "url_widget"], 0);
    let info = String::from_utf8_lossy(&out.stdout);
    assert!(
        info.contains(&format!("file://{}/index.json", repo.display())),
        "origin points at the sibling index: {info}"
    );

    // Publish 1.1.0 + the sibling index; a plain `iimod update` finds it.
    let manifest_path = payload.join("module.json");
    let manifest = std::fs::read_to_string(&manifest_path)
        .unwrap()
        .replace("\"1.0.0\"", "\"1.1.0\"");
    std::fs::write(&manifest_path, manifest).unwrap();
    let pkg2 = repo.join("url_widget-1.1.0.iimod");
    w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            pkg2.to_str().unwrap(),
            "--no-origin",
        ],
        0,
    );
    let sha = {
        use sha2::{Digest, Sha256};
        let mut h = Sha256::new();
        h.update(std::fs::read(&pkg2).unwrap());
        format!("{:x}", h.finalize())
    };
    std::fs::write(
        repo.join("index.json"),
        serde_json::json!({
            "indexVersion": 1,
            "modules": {"url_widget": {"version": "1.1.0", "url": "url_widget-1.1.0.iimod", "sha256": sha}}
        })
        .to_string(),
    )
    .unwrap();
    w.expect(&["update"], 0);
    let out = w.expect(&["info", "url_widget"], 0);
    assert!(String::from_utf8_lossy(&out.stdout).contains("1.1.0"));
}

#[test]
fn embedded_origin_beats_sibling_guess() {
    let w = World::new("emborigin");
    let payload = w.make_module("emb_widget", serde_json::json!({}));
    let mirror = w.root.join("mirror");
    std::fs::create_dir_all(&mirror).unwrap();
    let pkg = mirror.join("emb_widget-1.0.0.iimod");
    // Publisher embeds the canonical origin; the user installs from a mirror.
    w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            pkg.to_str().unwrap(),
            "--origin",
            "file:///canonical/repo/index.json",
        ],
        0,
    );
    let url = format!("file://{}", pkg.display());
    w.expect(&["install", &url], 0);
    let out = w.expect(&["info", "emb_widget"], 0);
    let info = String::from_utf8_lossy(&out.stdout);
    assert!(
        info.contains("file:///canonical/repo/index.json"),
        "embedded canonical origin wins over the mirror sibling: {info}"
    );
}

#[test]
fn pack_requires_origin_or_explicit_opt_out() {
    let w = World::new("packorigin");
    let payload = w.make_module("bare_widget", serde_json::json!({}));
    let out_pkg = w.root.join("bare_widget-1.0.0.iimod");

    // Neither --origin nor --no-origin → hard usage error, nothing written.
    let out = w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            out_pkg.to_str().unwrap(),
        ],
        2,
    );
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("--no-origin"),
        "error should mention the --no-origin escape hatch: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(!out_pkg.exists(), "no package should be written on failure");

    // --no-origin: packs fine, and installing it warns it carries no origin.
    w.expect(
        &[
            "pack",
            payload.to_str().unwrap(),
            "--out",
            out_pkg.to_str().unwrap(),
            "--no-origin",
        ],
        0,
    );
    let out = w.expect(&["install", out_pkg.to_str().unwrap()], 0);
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("no update origin"),
        "install should note the package has no update origin: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn vertical_bar_host_fence_present_and_optional() {
    // Modern stock tree: installing any module composes the vertical fence.
    let w = World::new("vbar");
    let payload = w.make_module("vbar_widget", serde_json::json!({}));
    w.expect(&["install", payload.to_str().unwrap()], 0);
    let vfile = w.ii().join("modules/ii/verticalBar/VerticalBarContent.qml");
    let text = std::fs::read_to_string(&vfile).unwrap();
    assert!(
        text.contains("iimp host/5"),
        "vertical fence composed: {text}"
    );
    assert!(text.contains("enabledBar"), "vertical repeater present");

    // Older stock tree without the vertical bar: everything still works and
    // nothing references the missing file.
    let w2 = World::new("vbar-old");
    std::fs::remove_file(
        w2.ii()
            .join("modules/ii/verticalBar/VerticalBarContent.qml"),
    )
    .unwrap();
    let payload2 = w2.make_module("oldtree_widget", serde_json::json!({}));
    w2.expect(&["install", payload2.to_str().unwrap()], 0);
    w2.expect(&["verify"], 0);
    w2.expect(&["repair"], 0);
    assert!(!w2
        .ii()
        .join("modules/ii/verticalBar/VerticalBarContent.qml")
        .exists());
}
