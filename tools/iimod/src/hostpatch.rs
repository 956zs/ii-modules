//! The IIMP host: fenced patches on stock files (P0–P5; see host_patches) +
//! QML files under
//! $II/mod/iimp/ + a sentinel. Embedded in the binary (single source of truth);
//! `ensure_host` is run by every mutating command (SPEC blueprint §1.8).

use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::exit::{self, bail};
use crate::hoststate::HostBundle;
use crate::manifest::PatchOp;
use crate::patch::{self, PatchInstance};
use crate::paths;

pub const HOST_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const HOST_OWNER: &str = "host";

/// Stock file hosting the vertical bar's content. Older dots revisions do
/// not ship it, so its host patch is OPTIONAL: it only joins the composition
/// when the file exists (see ops::all_stock_targets) and it is deliberately
/// NOT part of HOST_FILES / the wipe sentinel.
pub const VERTICAL_BAR_FILE: &str = "modules/ii/verticalBar/VerticalBarContent.qml";

/// The host patches (P0–P5). Anchors verified against dots-hyprland
/// 446504ad42; each is unique in its stock file. P5 targets the vertical
/// bar and is skipped entirely on stock trees that predate it.
pub fn embedded_host_patches() -> Vec<(&'static str, PatchInstance)> {
    let p = |index: u32, op: PatchOp, anchor: &str, content: &str| PatchInstance {
        owner: HOST_OWNER.into(),
        index,
        version: crate::hoststate::HOST_GENERATION.to_string(),
        op,
        anchor: anchor.into(),
        content: content.into(),
    };
    vec![
        // P0: import for the host type (shell.qml top-level imports).
        ("shell.qml", p(0, PatchOp::InsertAfter, "import \"panelFamilies\"", "import qs.mod.iimp\n")),
        // P1: instantiate the host inside ShellRoot.
        ("shell.qml", p(1, PatchOp::InsertAfter, "ReloadPopup {}", "    ModuleHost {}\n")),
        // P2: declared registry projection (JsonAdapter schema erasure guard).
        (
            "modules/common/Config.qml",
            p(
                2,
                PatchOp::InsertAfter,
                "property string panelFamily",
                concat!(
                    "            property JsonObject iimp: JsonObject {\n",
                    "                property list<string> enabledBar: []\n",
                    "                property list<string> enabledWindow: []\n",
                    // `property var` inside a JsonObject segfaults Quickshell's
                    // JsonAdapter deserializer (QQmlVMEMetaObject::writeProperty
                    // has no handling for writing a JSON object into a generic
                    // `var`-typed property). A JSON-encoded string is the
                    // supported representation; consumers JSON.parse it and
                    // reassign the whole string to trigger change notification.
                    "                property string barPlacementsJson: \"{}\"\n",
                    // Horizontal bar pages: JSON-encoded map of module id -> page
                    // index (0 = main page, the default). Same string encoding
                    // rationale as barPlacementsJson.
                    "                property string barPagesJson: \"{}\"\n",
                    // Bar order: JSON-encoded array of module ids. Enabled bar
                    // modules listed here come first, in this order (first id is
                    // rightmost in the horizontal bar, topmost in the vertical
                    // bar); unlisted ones follow in enabledBar order.
                    "                property string barOrderJson: \"[]\"\n",
                    "            }\n",
                ),
            ),
        ),
        // P3: bar slot host (renders left of the Weather group). The BarSlot
        // host asset owns the module Loaders and Bartender-style pages
        // (iimp.barPagesJson): one page shown at a time, every page kept
        // instantiated, width reserved for the widest page so nothing beside
        // it moves on a switch. The explicit preferred width stops the
        // RowLayout from latching the slot's last width when every module is
        // hidden; visibility follows the model count only, never a module's
        // effective visibility.
        (
            "modules/ii/bar/BarContent.qml",
            p(
                3,
                PatchOp::InsertBefore,
                "// Weather",
                concat!(
                    "            BarSlot {\n",
                    "                // Bar-slot modules with pages; see mod/iimp/BarSlot.qml.\n",
                    "                ids: Config.options.iimp?.enabledBar ?? []\n",
                    "                pagesJson: Config.options.iimp?.barPagesJson ?? \"{}\"\n",
                    "                orderJson: Config.options.iimp?.barOrderJson ?? \"[]\"\n",
                    "                barHovered: barRightSideMouseArea.hovered\n",
                    "                Layout.preferredWidth: implicitWidth\n",
                    "                Layout.leftMargin: implicitWidth > 0 ? 4 : 0\n",
                    "                Layout.fillHeight: true\n",
                    "            }\n",
                ),
            ),
        ),
        // P4: settings page entry before the pages[] terminator (leading comma
        // keeps "Quick" as the default pages[0]). The `    ]` anchor is shorter
        // than the manifest minimum: host patches are exempt from the length
        // heuristic (they ship in the binary, verified against the live tree at
        // release), and the engine's exactly-one-match rule still applies —
        // structurally this spot survives any change inside the page entries.
        (
            "settings.qml",
            p(
                4,
                PatchOp::InsertBefore,
                "    ]",
                "        ,{ name: Translation.tr(\"Modules\"), icon: \"extension\", component: \"mod/iimp/ModulesConfig.qml\" }\n",
            ),
        ),
        // P5: bar slot host in the VERTICAL bar (left/right placement) —
        // without it, bar modules silently vanish when bar.vertical is on.
        // Placement: the TOP section's otherwise-empty stretch (where the
        // horizontal bar shows the window title). The top section's height is
        // (bar - middle)/2 by stock design, so modules here can never collide
        // with the centred middle section — the bottom section can (it grows
        // upward into the centred clock/battery group). Declaration order
        // puts modules above the sidebar button; with none enabled the bar
        // is stock-identical. Modules read Config.options.bar.vertical
        // (baseline API) to adapt their layout. Model order: ids listed in
        // iimp.barOrderJson first (top to bottom), the rest in enabledBar
        // order — the same rule BarSlot.qml applies to the horizontal bar.
        (
            VERTICAL_BAR_FILE,
            p(
                5,
                PatchOp::InsertAfter,
                "spacing: 10",
                concat!(
                    "            Repeater {\n",
                    "                model: ((ids, order) => order.filter(id => ids.includes(id)).concat(ids.filter(id => !order.includes(id))))(Config.options.iimp?.enabledBar ?? [], JSON.parse(Config.options.iimp?.barOrderJson ?? \"[]\")).filter(id => ((JSON.parse(Config.options.iimp?.barPlacementsJson ?? \"{}\"))[id] ?? \"top\") !== \"bottom\")\n",
                    "                delegate: Loader {\n",
                    "                    required property string modelData\n",
                    "                    required property int index\n",
                    "                    Layout.alignment: Qt.AlignHCenter\n",
                    "                    Layout.topMargin: index === 0 ? Appearance.sizes.hyprlandGapsOut + 6 : 0\n",
                    "                    source: Quickshell.shellPath(`mod/${modelData}/bar.qml`)\n",
                    "                    onStatusChanged: if (status === Loader.Error) console.warn(`[iimp] bar module failed: ${modelData}`)\n",
                    "                }\n",
                    "            }\n",
                ),
            ),
        ),
        // P6: the same vertical-bar slot, alternative placement above the
        // tray. Per-module: iimp.barPlacementsJson is a JSON-encoded map of
        // module id -> "top" (default) | "bottom"; each module renders in
        // exactly one of P5/P6. Bottom placement can collide with the centred
        // middle section on busy bars (stock sections reserve no space from
        // each other); that trade-off is the user's to make.
        (
            VERTICAL_BAR_FILE,
            p(
                6,
                PatchOp::InsertBefore,
                "Bar.SysTray {",
                concat!(
                    "            Repeater {\n",
                    "                model: ((ids, order) => order.filter(id => ids.includes(id)).concat(ids.filter(id => !order.includes(id))))(Config.options.iimp?.enabledBar ?? [], JSON.parse(Config.options.iimp?.barOrderJson ?? \"[]\")).filter(id => ((JSON.parse(Config.options.iimp?.barPlacementsJson ?? \"{}\"))[id] ?? \"top\") === \"bottom\")\n",
                    "                delegate: Loader {\n",
                    "                    required property string modelData\n",
                    "                    Layout.alignment: Qt.AlignHCenter\n",
                    "                    Layout.bottomMargin: 4\n",
                    "                    source: Quickshell.shellPath(`mod/${modelData}/bar.qml`)\n",
                    "                    onStatusChanged: if (status === Loader.Error) console.warn(`[iimp] bar module failed: ${modelData}`)\n",
                    "                }\n",
                    "            }\n",
                ),
            ),
        ),
        // P7: BarContent import for the host types used by P3 (BarSlot).
        // Shares its anchor line with module patches (e.g. adaptive_bar);
        // anchors resolve against stripped stock text, so both coexist.
        (
            "modules/ii/bar/BarContent.qml",
            p(
                7,
                PatchOp::InsertAfter,
                "import qs.modules.common.functions",
                "import qs.mod.iimp\n",
            ),
        ),
    ]
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct HostSentinel {
    pub host_version: String,
    pub protocol_version: u32,
    #[serde(default)]
    pub host_generation: Option<u32>,
    #[serde(default)]
    pub content_id: Option<String>,
    pub installed_at_epoch: u64,
    #[serde(default)]
    pub qs_version_hint: Option<String>,
}

pub fn read_sentinel() -> Option<HostSentinel> {
    let bytes = std::fs::read(paths::host_sentinel()).ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// Generate mod/iimp/ModuleImports.qml: a statically-reachable file whose only
/// job is registering installed module dirs as QML modules (see ModuleHost).
pub fn module_imports_content(ids: &[String]) -> String {
    let mut content = String::from(
        "// GENERATED by iimod — do not edit. Registers module dirs as QML modules.\nimport QtQuick\n",
    );
    for id in ids {
        content.push_str(&format!("import qs.mod.{id}\n"));
    }
    content.push_str("\nQtObject {}\n");
    content
}

pub fn write_module_imports(ids: &[String]) -> Result<()> {
    let content = module_imports_content(ids);
    std::fs::create_dir_all(paths::host_dir())?;
    std::fs::write(paths::host_dir().join("ModuleImports.qml"), content)?;
    Ok(())
}

/// Wiped = registry says modules exist but the host sentinel is gone.
pub fn is_wiped(registry_nonempty: bool) -> bool {
    registry_nonempty && read_sentinel().is_none()
}

/// Write host QML files + sentinel and recompose the host patches into the
/// stock files (preserving all other modules' patches passed in `extra`).
/// Returns the list of stock files it rewrote.
pub fn ensure_host(
    bundle: &HostBundle,
    extra_patches_for: &dyn Fn(&str) -> Vec<PatchInstance>,
) -> Result<Vec<String>> {
    let ii = paths::ii_root();
    if !ii.join("shell.qml").exists() {
        return Err(bail(
            exit::STATE,
            format!(
                "shell tree not found at {} (is illogical-impulse installed?)",
                ii.display()
            ),
        ));
    }

    let mut order: Vec<String> = bundle
        .patches
        .iter()
        .filter(|stored| !stored.optional || ii.join(&stored.target).is_file())
        .map(|stored| stored.target.clone())
        .collect();
    order.sort();
    order.dedup();
    order.retain(|rel| rel != "shell.qml");
    if bundle
        .patches
        .iter()
        .any(|stored| stored.target == "shell.qml")
    {
        order.push("shell.qml".into());
    }

    let mut planned = Vec::new();
    for rel in order {
        let target = ii.join(&rel);
        let current = std::fs::read_to_string(&target)
            .map_err(|e| bail(exit::STATE, format!("cannot read stock file {rel}: {e}")))?;
        let mut set: Vec<PatchInstance> = bundle
            .patches
            .iter()
            .filter(|stored| stored.target == rel)
            .map(|stored| stored.patch.clone())
            .collect();
        set.extend(extra_patches_for(&rel));
        set.sort_by_key(|p| (p.owner.clone(), p.index));
        let composed = patch::recompose(&current, &set)?;
        if composed != current {
            planned.push((rel, target, composed));
        }
    }

    std::fs::create_dir_all(paths::host_dir())?;
    std::fs::write(
        paths::host_dir().join("ModuleHost.qml"),
        &bundle.module_host_qml,
    )?;
    std::fs::write(
        paths::host_dir().join("ModulesConfig.qml"),
        &bundle.modules_config_qml,
    )?;
    std::fs::write(paths::host_dir().join("BarSlot.qml"), &bundle.bar_slot_qml)?;
    if !paths::host_dir().join("ModuleImports.qml").exists() {
        write_module_imports(&[])?;
    }

    let mut touched = Vec::new();
    for (rel, target, composed) in planned {
        std::fs::write(&target, composed)?;
        touched.push(rel);
    }

    let sentinel = HostSentinel {
        host_version: HOST_VERSION.to_string(),
        protocol_version: bundle.descriptor.protocol_version,
        host_generation: Some(bundle.descriptor.generation),
        content_id: Some(bundle.descriptor.content_id.clone()),
        installed_at_epoch: crate::registry::now_epoch(),
        qs_version_hint: crate::qs::qs_version(),
    };
    std::fs::write(
        paths::host_sentinel(),
        serde_json::to_string_pretty(&sentinel)? + "\n",
    )?;
    // Make sure per-module config dir exists for ConfigLoader-pattern writers.
    std::fs::create_dir_all(paths::modules_config_dir())?;
    Ok(touched)
}

/// Remove host patches and files (used only by `doctor --remove-host` when no
/// modules remain installed).
#[allow(dead_code)] // reserved for doctor --remove-host
pub fn remove_host(extra_patches_for: &dyn Fn(&str) -> Vec<PatchInstance>) -> Result<()> {
    let ii = paths::ii_root();
    // Removal order: shell.qml FIRST (stop referencing before files vanish).
    for rel in [
        "shell.qml",
        "modules/common/Config.qml",
        "modules/ii/bar/BarContent.qml",
        "settings.qml",
    ] {
        let target = ii.join(rel);
        if !target.exists() {
            continue;
        }
        let current = std::fs::read_to_string(&target)?;
        let set = extra_patches_for(rel); // everything except host
        let composed = patch::recompose(&current, &set)?;
        if composed != current {
            std::fs::write(&target, composed)?;
        }
    }
    if paths::host_dir().exists() {
        std::fs::remove_dir_all(paths::host_dir())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_patch_contents_pass_engine_rules() {
        // Single-line anchors; content fence-injection-free. (Host anchors are
        // exempt from the ≥10-char manifest heuristic — see P4 note.)
        for (file, p) in embedded_host_patches() {
            assert!(
                !p.anchor.is_empty() && !p.anchor.contains('\n'),
                "{file}: bad anchor"
            );
            for line in p.content.lines() {
                assert!(
                    !line.contains(">>> iimp ") && !line.contains("<<< iimp "),
                    "{file}: fence injection"
                );
            }
        }
    }

    #[test]
    fn compose_host_onto_stock_snippets() {
        // Miniature stand-ins reproducing the anchor lines of the real files.
        let shell = "import \"panelFamilies\"\n\nShellRoot {\n    ReloadPopup {}\n}\n";
        let set: Vec<PatchInstance> = embedded_host_patches()
            .into_iter()
            .filter(|(f, _)| *f == "shell.qml")
            .map(|(_, p)| p)
            .collect();
        let composed = crate::patch::compose(shell, &set).unwrap();
        assert!(composed.contains("import qs.mod.iimp"));
        assert!(composed.contains("ModuleHost {}"));
        let (stripped, _) = crate::patch::strip(&composed).unwrap();
        assert_eq!(stripped, shell);
    }

    #[test]
    fn horizontal_bar_slot_delegates_to_host_asset() {
        let patches = embedded_host_patches();
        let (_, p3) = patches
            .iter()
            .find(|(file, p)| *file == "modules/ii/bar/BarContent.qml" && p.index == 3)
            .expect("P3 present");
        let content = p3.content.as_str();
        assert!(content.starts_with("            BarSlot {\n"));
        assert!(content.ends_with("            }\n"));
        assert!(content.contains("ids: Config.options.iimp?.enabledBar ?? []\n"));
        assert!(content.contains("pagesJson: Config.options.iimp?.barPagesJson ?? \"{}\"\n"));
        assert!(content.contains("orderJson: Config.options.iimp?.barOrderJson ?? \"[]\"\n"));
        assert!(content.contains("barHovered: barRightSideMouseArea.hovered\n"));
        assert!(content.contains("Layout.preferredWidth: implicitWidth\n"));
        // No visibility binding in the patch: the asset decides from its
        // model count, never from a module's effective visibility.
        assert!(!content.contains("visible:"));
        assert_eq!(content.matches('{').count(), content.matches('}').count());
        // P7 brings the host type into BarContent.
        let (_, p7) = patches
            .iter()
            .find(|(file, p)| *file == "modules/ii/bar/BarContent.qml" && p.index == 7)
            .expect("P7 present");
        assert_eq!(p7.content, "import qs.mod.iimp\n");
        // Config projection declares the page map.
        let (_, p2) = patches
            .iter()
            .find(|(file, p)| *file == "modules/common/Config.qml" && p.index == 2)
            .expect("P2 present");
        assert!(p2
            .content
            .contains("property string barPagesJson: \"{}\"\n"));
        assert!(p2
            .content
            .contains("property string barOrderJson: \"[]\"\n"));
    }

    #[test]
    fn vertical_bar_slots_apply_bar_order_before_placement() {
        let patches = embedded_host_patches();
        for index in [5, 6] {
            let (_, p) = patches
                .iter()
                .find(|(file, p)| *file == VERTICAL_BAR_FILE && p.index == index)
                .expect("vertical patch present");
            let model = p
                .content
                .lines()
                .find(|l| l.trim_start().starts_with("model:"))
                .expect("model line");
            // Listed ids first, unlisted appended in enabledBar order, then
            // the placement filter — same rule as BarSlot.qml.
            assert!(model.contains("order.filter(id => ids.includes(id)).concat(ids.filter(id => !order.includes(id)))"));
            assert!(model.contains("JSON.parse(Config.options.iimp?.barOrderJson ?? \"[]\")"));
            let order_at = model.find("barOrderJson").unwrap();
            let filter_at = model
                .find(".filter(id => ((JSON.parse(Config.options.iimp?.barPlacementsJson")
                .unwrap();
            assert!(order_at < filter_at);
        }
    }

    #[test]
    fn bar_slot_asset_keeps_pages_instantiated_and_collapses_hidden_modules() {
        let slot = include_str!("../assets/BarSlot.qml");
        // Same collapse rule as before: width, never Loader.visible, follows
        // item.visible; the root hides only from the model count.
        assert!(slot.contains("readonly property bool shown: item !== null && item.visible"));
        assert!(slot.contains("width: shown ? item.implicitWidth : 0"));
        assert!(slot.contains("visible: (root.ids ?? []).length > 0"));
        // Non-current pages stay visible (effective visibility!) and fade.
        assert!(slot.contains("opacity: current ? 1 : 0"));
        assert!(slot.contains("enabled: current"));
        assert!(!slot.contains("visible: current"));
        // Reserved width of the widest page keeps neighbours still.
        assert!(slot.contains("width: root.pagesWidth"));
        // Modules render in bar order within their page.
        assert!(slot.contains("property string orderJson: \"[]\""));
        assert!(slot.contains(
            "model: root.orderedIds.filter(id => root.pageOf(id) === pageRow.modelData)"
        ));
        assert!(slot.contains("widest = Math.max(widest, page.implicitWidth);"));
        // Paging: cycle, malformed JSON -> main page, auto return.
        assert!(slot.contains(
            "root.pageIndex = root.pageCount > 0 ? (root.pageIndex + 1) % root.pageCount : 0;"
        ));
        assert!(slot.contains("return Number.isInteger(page) && page > 0 ? page : 0;"));
        assert!(slot.contains("interval: 5000"));
        // No FINAL anchor-line names on the Item root.
        for name in [
            "property bool bottom",
            "property bool top",
            "property var left",
            "property var right",
        ] {
            assert!(!slot.contains(name), "{name}");
        }
        assert_eq!(slot.matches('{').count(), slot.matches('}').count());
    }

    #[test]
    fn module_host_asset_uses_underscore_id_grammar() {
        let module_host_qml = include_str!("../assets/ModuleHost.qml");
        assert!(module_host_qml.contains(r"/^[a-z][a-z0-9_]{1,30}$/"));
        assert!(!module_host_qml.contains(r"/^[a-z][a-z0-9-]{1,30}$/"));
    }
}
