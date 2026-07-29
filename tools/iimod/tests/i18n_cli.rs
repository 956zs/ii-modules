use std::path::{Path, PathBuf};
use std::process::Output;

fn bin() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_iimod"))
}

fn temp_root(name: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("iimod-i18n-it-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn make_module(root: &Path, id: &str, qml: &str) -> PathBuf {
    let payload = root.join(id);
    std::fs::create_dir_all(payload.join("translations")).unwrap();
    let manifest = serde_json::json!({
        "protocolVersion": 1,
        "id": id,
        "name": {"en_US": id},
        "description": {"en_US": "i18n fixture"},
        "version": "1.0.0",
        "authors": ["test"],
        "license": "MIT",
        "slots": ["bar"],
        "compat": {"probes": []},
        "capabilities": []
    });
    std::fs::write(
        payload.join("module.json"),
        serde_json::to_string_pretty(&manifest).unwrap() + "\n",
    )
    .unwrap();
    std::fs::write(payload.join("bar.qml"), qml).unwrap();
    payload
}

fn run(args: &[&str]) -> Output {
    run_in(None, args)
}

fn run_in(current_dir: Option<&Path>, args: &[&str]) -> Output {
    let mut command = std::process::Command::new(bin());
    command.args(args).env("IIMOD_NO_QS", "1");
    if let Some(current_dir) = current_dir {
        command.current_dir(current_dir);
    }
    command.output().expect("spawn iimod")
}

fn write_dict(payload: &Path, locale: &str, entries: serde_json::Value) {
    std::fs::write(
        payload.join("translations").join(format!("{locale}.json")),
        serde_json::to_string_pretty(&entries).unwrap() + "\n",
    )
    .unwrap();
}

fn write_manifest(payload: &Path, update: impl FnOnce(&mut serde_json::Value)) {
    let path = payload.join("module.json");
    let mut manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    update(&mut manifest);
    std::fs::write(
        path,
        serde_json::to_string_pretty(&manifest).unwrap() + "\n",
    )
    .unwrap();
}

#[test]
fn extract_directory_emits_deterministic_json() {
    let root = temp_root("extract-directory");
    let payload = make_module(
        &root,
        "sample_mod",
        "Item {\n  property string z: Translation.tr(\"Zulu\")\n  property string a: Translation.tr('Alpha')\n}\n",
    );

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        "{\n  \"module\": \"sample_mod\",\n  \"sources\": [\n    \"Alpha\",\n    \"Zulu\"\n  ]\n}\n"
    );
}

#[test]
fn extract_scans_template_interpolations_at_original_locations() {
    let root = temp_root("template-interpolation");
    let payload = make_module(
        &root,
        "template_mod",
        "Item {\n  property string text: `raw Translation.tr(\"Ignored raw\") ${\n    Translation.tr(\"Inside interpolation\")\n  }`\n}\n",
    );

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()["sources"],
        serde_json::json!(["Inside interpolation"])
    );

    std::fs::write(
        payload.join("bar.qml"),
        "Item {\n  property string text: `raw ${\n    Translation.tr(modelData.label)\n  }`\n}\n",
    )
    .unwrap();
    let dynamic = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(dynamic.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&dynamic.stderr);
    assert!(stderr.contains("bar.qml:3:5:"), "{stderr}");
}

#[test]
fn extract_finds_nested_calls_inside_immediate_arg_arguments() {
    let root = temp_root("nested-immediate-arg");
    let payload = make_module(
        &root,
        "nested_arg_mod",
        "Item { property string text: Translation.tr(\"Outer %1\").arg(Translation.tr(\"Inner\")) }\n",
    );

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()["sources"],
        serde_json::json!(["Inner", "Outer %1"])
    );
}

#[test]
fn extract_ignores_regex_literals_after_expression_keywords() {
    let root = temp_root("keyword-regex");
    let payload = make_module(
        &root,
        "keyword_regex_mod",
        r#"Item {
  function regexes(value, total, count, divisor) {
    const returned = function() { return /Translation.tr("Ignored return")/; }
    try { throw /Translation.tr("Ignored throw")/; } catch (error) {}
    switch (value) { case /Translation.tr("Ignored case")/: break; }
    const typed = typeof /Translation.tr("Ignored typeof")/
    const discarded = void /Translation.tr("Ignored void")/
    const deleted = delete /Translation.tr("Ignored delete")/.unused
    const ratio = total / count / divisor
    const previousRegex = (/Translation.tr("Ignored previous regex")/).test(value)
    return returned() && ratio && previousRegex
  }
  property string text: Translation.tr("Real source")
}
"#,
    );

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()["sources"],
        serde_json::json!(["Real source"])
    );
}

#[test]
fn extract_rejects_unrelated_enclosing_group_arg_chains() {
    let root = temp_root("unrelated-group-arg");
    let payload = make_module(
        &root,
        "group_arg_mod",
        "Item { property var value: ({ value: Translation.tr(\"Needs %1\") }).arg(value) }\n",
    );

    for qml in [
        "Item { property var value: ({ value: Translation.tr(\"Needs %1\") }).arg(value) }\n",
        "Item { property var value: ([Translation.tr(\"Needs %1\")]).arg(value) }\n",
        "Item { property var value: (ok ? Translation.tr(\"Needs %1\") : \"plain\").arg(value) }\n",
    ] {
        std::fs::write(payload.join("bar.qml"), qml).unwrap();
        let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
        assert_eq!(
            output.status.code(),
            Some(3),
            "qml={qml}\nstdout={}\nstderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            String::from_utf8_lossy(&output.stderr).contains("requires 1 immediate .arg() call"),
            "qml={qml}\nstderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
fn extract_ignores_statement_regexes_after_control_flow() {
    let root = temp_root("control-flow-regex");
    let payload = make_module(
        &root,
        "control_regex_mod",
        r#"Item {
  function regexes(value, values) {
    if (value) /Translation.tr("Ignored if")/.test(value)
    while (value) /Translation.tr("Ignored while")/.test(value)
    for (const item of values) /Translation.tr("Ignored for")/.test(item)
    with (value) /Translation.tr("Ignored with")/.test(value)
    try { throw value } catch (error) /Translation.tr("Ignored catch")/.test(error)
    switch (value) { default: break }
    /users:\\(\\(\"([^\"]+)\",pid=\\d+/.test(value);
    /Translation.tr("Ignored block")/.test(value)
    if (value) value = false; else /Translation.tr("Ignored else")/.test(value)
    return Translation.tr("Real source")
  }
}
"#,
    );

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()["sources"],
        serde_json::json!(["Real source"])
    );
}

#[test]
fn extract_keeps_division_after_call_and_object_expressions() {
    let root = temp_root("division-after-expressions");
    let payload = make_module(
        &root,
        "division_mod",
        r#"Item {
  property real callRatio: measure() / Translation.tr("Call divisor")
  property real objectRatio: ({ value: 1 }).value / Translation.tr("Object divisor")
}
"#,
    );

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()["sources"],
        serde_json::json!(["Call divisor", "Object divisor"])
    );
}

#[test]
fn cli_shape_requires_exactly_one_source_mode() {
    for args in [
        vec!["i18n", "extract"],
        vec!["i18n", "extract", "sample", "--all"],
        vec!["i18n", "check"],
        vec!["i18n", "check", "sample", "--all"],
    ] {
        let output = run(&args);
        assert_eq!(
            output.status.code(),
            Some(2),
            "args={args:?}\nstderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let help = run(&["i18n", "--help"]);
    assert_eq!(help.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&help.stdout);
    assert!(stdout.contains("extract") && stdout.contains("check"));
}

#[test]
fn extract_directory_and_package_match() {
    let root = temp_root("extract-package");
    let payload = make_module(
        &root,
        "package_mod",
        "Item { property string text: Translation.tr(\"Packaged\") }\n",
    );
    write_dict(&payload, "zh_TW", serde_json::json!({"Packaged": "已封裝"}));
    let package = root.join("package_mod.iimod");
    let pack = run(&[
        "pack",
        payload.to_str().unwrap(),
        "--out",
        package.to_str().unwrap(),
        "--no-origin",
    ]);
    assert_eq!(
        pack.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&pack.stderr)
    );

    let directory = run(&["i18n", "extract", payload.to_str().unwrap()]);
    let archive = run(&["i18n", "extract", package.to_str().unwrap()]);
    assert_eq!(directory.status.code(), Some(0));
    assert_eq!(archive.status.code(), Some(0));
    assert_eq!(archive.stdout, directory.stdout);
}

#[test]
fn check_defaults_locales_overrides_and_orphan_policy() {
    let root = temp_root("check-locales");
    let payload = make_module(
        &root,
        "check_mod",
        "Item { property string text: Translation.tr(\"Ready\") }\n",
    );
    write_dict(
        &payload,
        "zh_TW",
        serde_json::json!({"Orphan": "額外", "Ready": "就緒"}),
    );

    let warned = run(&["i18n", "check", payload.to_str().unwrap()]);
    assert_eq!(warned.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&warned.stderr).contains("orphan key"));

    let denied = run(&["i18n", "check", payload.to_str().unwrap(), "--deny-orphans"]);
    assert_eq!(denied.status.code(), Some(3));

    let override_locale = run(&[
        "i18n",
        "check",
        payload.to_str().unwrap(),
        "--locale",
        "ja_JP",
    ]);
    assert_eq!(override_locale.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&override_locale.stderr).contains("ja_JP"));
}

#[test]
fn validate_rejects_missing_zh_tw_source_key() {
    let root = temp_root("validate-missing-zh-tw-key");
    let payload = make_module(
        &root,
        "validate_missing_key",
        "Item { property string text: Translation.tr(\"Ready\") }\n",
    );
    write_dict(&payload, "zh_TW", serde_json::json!({}));

    let output = run(&["validate", payload.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("zh_TW: missing key \"Ready\""), "{stderr}");
}

#[test]
fn validate_rejects_missing_and_malformed_required_catalogs_with_exit_3() {
    let root = temp_root("validate-required-catalog");
    let payload = make_module(
        &root,
        "validate_catalog",
        "Item { property string text: Translation.tr(\"Ready\") }\n",
    );

    let missing = run(&["validate", payload.to_str().unwrap()]);
    assert_eq!(missing.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&missing.stderr).contains("missing required locale zh_TW"));

    std::fs::write(payload.join("translations/zh_TW.json"), "{not json}\n").unwrap();
    let malformed = run(&["validate", payload.to_str().unwrap()]);
    assert_eq!(malformed.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&malformed.stderr).contains("translations/zh_TW.json"));
}

#[test]
fn validate_rejects_undeclared_dynamic_translation_call() {
    let root = temp_root("validate-dynamic-error");
    let payload = make_module(
        &root,
        "validate_dynamic",
        "Item { property string text: Translation.tr(modelData.label) }\n",
    );
    write_dict(&payload, "zh_TW", serde_json::json!({}));

    let output = run(&["validate", payload.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("bar.qml:1:"), "{stderr}");
    assert!(
        stderr.contains("has no exact i18n.sources.json declaration"),
        "{stderr}"
    );
}

#[test]
fn validate_reports_orphan_and_identical_values_as_warnings() {
    let root = temp_root("validate-i18n-warnings");
    let payload = make_module(
        &root,
        "validate_warnings",
        "Item { property string text: Translation.tr(\"Ready\") }\n",
    );
    write_dict(
        &payload,
        "zh_TW",
        serde_json::json!({"Orphan": "額外", "Ready": "Ready"}),
    );

    let output = run(&["validate", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("warning:"), "{stdout}");
    assert!(stdout.contains("orphan key"), "{stdout}");
    assert!(
        stdout.contains("translation is identical to source"),
        "{stdout}"
    );
}

#[test]
fn strict_release_locales_reject_missing_zh_cn_and_orphans() {
    let root = temp_root("strict-release-locales");
    let payload = make_module(
        &root,
        "strict_release",
        "Item { property string text: Translation.tr(\"Ready\") }\n",
    );
    write_dict(&payload, "zh_TW", serde_json::json!({"Ready": "就緒"}));

    let args = [
        "i18n",
        "check",
        payload.to_str().unwrap(),
        "--locale",
        "zh_TW",
        "--locale",
        "zh_CN",
        "--deny-orphans",
    ];
    let missing = run(&args);
    assert_eq!(missing.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&missing.stderr).contains("missing required locale zh_CN"));

    write_dict(
        &payload,
        "zh_CN",
        serde_json::json!({"Orphan": "多余", "Ready": "就绪"}),
    );
    let orphan = run(&args);
    assert_eq!(orphan.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&orphan.stderr).contains("orphan key \"Orphan\""));
}

#[test]
fn repository_all_is_direct_sorted_and_checks_shared_values() {
    let root = temp_root("repository-all");
    std::fs::create_dir_all(root.join("tools/iimod")).unwrap();
    std::fs::write(root.join("tools/iimod/Cargo.toml"), "[package]\n").unwrap();
    let modules = root.join("modules");
    std::fs::create_dir_all(&modules).unwrap();
    let beta = make_module(
        &modules,
        "beta_mod",
        "Item { property string text: Translation.tr(\"Shared\") }\n",
    );
    let alpha = make_module(
        &modules,
        "alpha_mod",
        "Item { property string text: Translation.tr(\"Shared\") }\n",
    );
    for payload in [&alpha, &beta] {
        write_dict(payload, "zh_TW", serde_json::json!({"Shared": "共用"}));
        write_dict(payload, "zh_CN", serde_json::json!({"Shared": "共享"}));
    }
    let nested = modules.join("group/nested_mod");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::write(nested.join("module.json"), "not json").unwrap();

    let extracted = run_in(Some(&root.join("tools")), &["i18n", "extract", "--all"]);
    assert_eq!(
        extracted.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&extracted.stderr)
    );
    let stdout = String::from_utf8(extracted.stdout).unwrap();
    assert!(stdout.find("alpha_mod").unwrap() < stdout.find("beta_mod").unwrap());
    assert!(!stdout.contains("nested_mod"));

    let checked = run_in(Some(&root), &["i18n", "check", "--all"]);
    assert_eq!(
        checked.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&checked.stderr)
    );

    write_dict(&beta, "zh_CN", serde_json::json!({"Shared": "不同"}));
    let conflict = run_in(Some(&root), &["i18n", "check", "--all"]);
    assert_eq!(conflict.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&conflict.stderr);
    assert!(stderr.contains("alpha_mod=\"共享\""), "{stderr}");
    assert!(stderr.contains("beta_mod=\"不同\""), "{stderr}");

    write_dict(
        &alpha,
        "zh_CN",
        serde_json::json!({"Orphan shared": "甲", "Shared": "共享"}),
    );
    write_dict(
        &beta,
        "zh_CN",
        serde_json::json!({"Orphan shared": "乙", "Shared": "共享"}),
    );
    let orphan_conflict = run_in(Some(&root), &["i18n", "check", "--all"]);
    assert_eq!(orphan_conflict.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&orphan_conflict.stderr);
    assert!(stderr.contains("Orphan shared"), "{stderr}");
    assert!(stderr.contains("alpha_mod=\"甲\""), "{stderr}");
    assert!(stderr.contains("beta_mod=\"乙\""), "{stderr}");

    let mismatched = make_module(&modules, "wrong_dir", "Item {}\n");
    write_manifest(&mismatched, |manifest| {
        manifest["id"] = serde_json::Value::String("different_id".into());
    });
    let mismatch = run_in(Some(&root), &["i18n", "extract", "--all"]);
    assert_eq!(mismatch.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&mismatch.stderr).contains("payload dir"));
}

#[test]
fn manifest_patch_and_dynamic_declarations_share_the_scanner() {
    let root = temp_root("patch-dynamic");
    let payload = make_module(
        &root,
        "dynamic_mod",
        "Item { property string text: Translation.tr( modelData.label ) }\n",
    );
    write_manifest(&payload, |manifest| {
        manifest["patches"] = serde_json::json!([{
            "file": "settings.qml",
            "op": "insert-after",
            "anchor": "long enough anchor",
            "content": "Item { text: Translation.tr(modelData.label) }"
        }]);
    });
    std::fs::write(
        payload.join("i18n.sources.json"),
        "{\n  \"schemaVersion\": 1,\n  \"declarations\": [\n    {\n      \"source\": \"bar.qml\",\n      \"expression\": \"modelData.label\",\n      \"sources\": [\n        \"Dynamic B\",\n        \"Dynamic A\"\n      ]\n    },\n    {\n      \"source\": \"module.json#patches/0/content\",\n      \"expression\": \"modelData.label\",\n      \"sources\": [\n        \"Patched dynamic\"\n      ]\n    }\n  ]\n}\n",
    )
    .unwrap();

    let output = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()["sources"],
        serde_json::json!(["Dynamic A", "Dynamic B", "Patched dynamic"])
    );

    std::fs::write(
        payload.join("i18n.sources.json"),
        "{\"schemaVersion\":1,\"declarations\":[{\"source\":\"bar.qml\",\"expression\":\"modelData.label\",\"sources\":[\"Dynamic A\"]}]}\n",
    )
    .unwrap();
    let missing_patch = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(missing_patch.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&missing_patch.stderr);
    assert!(
        stderr.contains("module.json#patches/0/content:1:"),
        "{stderr}"
    );
    assert!(stderr.contains("no exact"), "{stderr}");

    std::fs::write(
        payload.join("i18n.sources.json"),
        "{\"schemaVersion\":1,\"declarations\":[{\"source\":\"bar.qml\",\"expression\":\"modelData.label\",\"sources\":[\"Dynamic A\"]},{\"source\":\"module.json#patches/0/content\",\"expression\":\"modelData.label\",\"sources\":[\"Patched dynamic\"]},{\"source\":\"module.json#patches/0/content\",\"expression\":\"missing\",\"sources\":[\"Stale\"]}]}\n",
    )
    .unwrap();
    let stale = run(&["i18n", "extract", payload.to_str().unwrap()]);
    assert_eq!(stale.status.code(), Some(3));
    let stderr = String::from_utf8_lossy(&stale.stderr);
    assert!(
        stderr.contains("unmatched declaration for module.json#patches/0/content"),
        "{stderr}"
    );
    assert!(stderr.contains("missing"), "{stderr}");
}

#[test]
fn check_directory_and_package_match() {
    let root = temp_root("check-package");
    let payload = make_module(
        &root,
        "package_check",
        "Item { property string text: Translation.tr(\"Ready\") }\n",
    );
    write_dict(&payload, "zh_TW", serde_json::json!({"Ready": "就緒"}));
    let package = root.join("package_check.iimod");
    let packed = run(&[
        "pack",
        payload.to_str().unwrap(),
        "--out",
        package.to_str().unwrap(),
        "--no-origin",
    ]);
    assert_eq!(packed.status.code(), Some(0));

    let directory = run(&["i18n", "check", payload.to_str().unwrap()]);
    let archive = run(&["i18n", "check", package.to_str().unwrap()]);
    assert_eq!(directory.status.code(), Some(0));
    assert_eq!(archive.status.code(), Some(0));
    assert_eq!(archive.stdout, directory.stdout);
    assert_eq!(archive.stderr, directory.stderr);
}
