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
        std::fs::write(payload.join("module.json"), serde_json::to_string_pretty(&manifest).unwrap()).unwrap();
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
                let rel = path.strip_prefix(root).unwrap().to_string_lossy().into_owned();
                let mut hasher = Sha256::new();
                hasher.update(std::fs::read(&path).unwrap());
                map.insert(rel, format!("{:x}", hasher.finalize()));
            }
        }
    }
    walk(root, root, &mut map);
    map
}

#[test]
fn tier_a_install_uninstall_byte_clean() {
    let w = World::new("tier-a-clean");
    let pristine = w.hash_ii();
    let payload = w.make_module("hello-widget", serde_json::json!({}));

    w.expect(&["validate", payload.to_str().unwrap()], 0);
    w.expect(&["check", payload.to_str().unwrap()], 0);
    w.expect(&["install", payload.to_str().unwrap()], 0);

    // Host patches landed; module dir exists; projections written.
    let shell = std::fs::read_to_string(w.ii().join("shell.qml")).unwrap();
    assert!(shell.contains("import qs.mod.iimp") && shell.contains("ModuleHost {}"));
    assert!(w.ii().join("mod/hello-widget/bar.qml").exists());
    assert!(w.ii().join("mod/iimp/ModuleHost.qml").exists());
    let config = std::fs::read_to_string(w.root.join("shellconfig/config.json")).unwrap();
    assert!(config.contains("hello-widget"));
    let translations =
        std::fs::read_to_string(w.root.join("shellconfig/translations/zh_TW.json")).unwrap();
    assert!(translations.contains("你好"));
    w.expect(&["verify"], 0);

    // Uninstall → host stays (harmless), module gone, translations unmerged.
    w.expect(&["uninstall", "hello-widget"], 0);
    assert!(!w.ii().join("mod/hello-widget").exists());
    let translations =
        std::fs::read_to_string(w.root.join("shellconfig/translations/zh_TW.json")).unwrap();
    assert!(!translations.contains("你好"));

    // Byte-clean modulo the host (strip host = pristine): compare stripped stock files.
    for rel in ["shell.qml", "modules/common/Config.qml", "modules/ii/bar/BarContent.qml", "settings.qml"] {
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
        assert_eq!(&format!("{:x}", hasher.finalize()), pristine_content_hash, "{rel} not byte-clean after strip");
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
    let payload_b = w.make_module("bbb-patcher", tier_b);

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
    let payload_a = w.make_module("aaa-patcher", tier_a2);

    // Install order B then A.
    w.expect(&["install", payload_b.to_str().unwrap(), "--allow-patches"], 0);
    w.expect(&["install", payload_a.to_str().unwrap(), "--allow-patches"], 0);
    let bytes_ba = std::fs::read_to_string(w.ii().join("modules/ii/bar/BarContent.qml")).unwrap();

    // Fresh world, install order A then B → identical bytes (determinism law).
    let w2 = World::new("tier-b-order2");
    let payload_b2 = w2.make_module("bbb-patcher", serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-before",
            "anchor": "            // Weather",
            "content": "            BbbThing {}\n"
        }],
    }));
    let payload_a2 = w2.make_module("aaa-patcher", serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-before",
            "anchor": "            // Weather",
            "content": "            AaaThing {}\n"
        }],
    }));
    w2.expect(&["install", payload_a2.to_str().unwrap(), "--allow-patches"], 0);
    w2.expect(&["install", payload_b2.to_str().unwrap(), "--allow-patches"], 0);
    let bytes_ab = std::fs::read_to_string(w2.ii().join("modules/ii/bar/BarContent.qml")).unwrap();
    assert_eq!(bytes_ba, bytes_ab, "install order must not affect bytes");
    assert!(bytes_ab.find("AaaThing").unwrap() < bytes_ab.find("BbbThing").unwrap());

    // Bad anchor → exit 8 at check time.
    let bad = w.make_module("bad-anchor", serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-after",
            "anchor": "THIS ANCHOR EXISTS NOWHERE",
            "content": "            Nope {}\n"
        }],
    }));
    w.expect(&["check", bad.to_str().unwrap()], 8);
}

#[test]
fn dependency_enforcement() {
    let w = World::new("deps");
    let dependent = w.make_module("needs-core", serde_json::json!({
        "requires": {"modules": [{"id": "core-lib", "versionReq": ">=1.0, <2"}]}
    }));
    // Missing dep → exit 5.
    w.expect(&["install", dependent.to_str().unwrap()], 5);

    let core = w.make_module("core-lib", serde_json::json!({}));
    w.expect(&["install", core.to_str().unwrap()], 0);
    w.expect(&["install", dependent.to_str().unwrap()], 0);

    // Uninstalling the dependency without cascade → exit 5; with cascade → both gone.
    w.expect(&["uninstall", "core-lib"], 5);
    w.expect(&["uninstall", "core-lib", "--cascade"], 0);
    assert!(!w.ii().join("mod/needs-core").exists());
    assert!(!w.ii().join("mod/core-lib").exists());
}

#[test]
fn wipe_and_reapply_restores_byte_identical() {
    let w = World::new("wipe");
    let payload = w.make_module("survivor", serde_json::json!({
        "patches": [{
            "file": "modules/ii/bar/BarContent.qml",
            "op": "insert-before",
            "anchor": "            // Weather",
            "content": "            Survivor {}\n"
        }],
    }));
    w.expect(&["install", payload.to_str().unwrap(), "--allow-patches"], 0);
    let installed_state = w.hash_ii();

    // Simulate a dots update: reset ONLY the ii tree to stock (state survives).
    std::fs::remove_dir_all(w.ii()).unwrap();
    write_stock_tree(&w.ii());
    assert!(!w.ii().join("mod").exists());

    // Detection + block.
    w.expect(&["verify"], 7);
    w.expect(&["install", w.root.join("src/survivor").to_str().unwrap()], 7);

    // Reapply → byte-identical to pre-wipe.
    w.expect(&["reapply"], 0);
    assert_eq!(w.hash_ii(), installed_state, "reapply must restore byte-identical tree");
    w.expect(&["verify"], 0);
}

#[test]
fn pack_install_roundtrip_and_tamper() {
    let w = World::new("pack");
    let payload = w.make_module("packed-mod", serde_json::json!({}));
    let out_pkg = w.root.join("packed-mod-1.0.0.iimod");
    w.expect(&["pack", payload.to_str().unwrap(), "--out", out_pkg.to_str().unwrap()], 0);
    w.expect(&["install", out_pkg.to_str().unwrap()], 0);
    w.expect(&["uninstall", "packed-mod"], 0);

    // Tamper one byte inside the gzip → integrity/validation failure, not success.
    let mut bytes = std::fs::read(&out_pkg).unwrap();
    let len = bytes.len();
    bytes[len - 20] ^= 0xff;
    let bad_pkg = w.root.join("tampered.iimod");
    std::fs::write(&bad_pkg, bytes).unwrap();
    let out = w.run(&["install", bad_pkg.to_str().unwrap()]);
    assert_ne!(out.status.code(), Some(0), "tampered package must not install");
}

#[test]
fn enable_disable_projection() {
    let w = World::new("toggle");
    let payload = w.make_module("toggle-me", serde_json::json!({}));
    w.expect(&["install", payload.to_str().unwrap()], 0);

    let config = || std::fs::read_to_string(w.root.join("shellconfig/config.json")).unwrap();
    assert!(config().contains("toggle-me"));
    w.expect(&["disable", "toggle-me"], 0);
    assert!(!config().replace("\"enabledWindow\": []", "").contains("toggle-me") || {
        let v: serde_json::Value = serde_json::from_str(&config()).unwrap();
        v["iimp"]["enabledBar"].as_array().unwrap().is_empty()
    });
    w.expect(&["enable", "toggle-me"], 0);
    let v: serde_json::Value = serde_json::from_str(&config()).unwrap();
    assert_eq!(v["iimp"]["enabledBar"][0], "toggle-me");
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
