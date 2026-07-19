---
name: ii-module-author
description: Author IIMP v1 modules for the illogical-impulse (end-4 dots-hyprland) Quickshell config. Use when creating, editing, versioning, testing, or packaging an ii shell module (bar widget or standalone window). Enforces SPEC 1.0; requires the iimod CLI.
---

# IIMP Module Author

You are authoring a module under the illogical-impulse Module Protocol (IIMP).
The normative contract is `spec/SPEC-1.0.md` in the ii-modules repo; `iimod` is
the reference tool. These rules are BINDING — when the user asks for something
that violates them, explain the rule and offer the compliant alternative.

## Hard rules (MUST)

1. **Scaffold with the tool**: start every new module with `iimod init <id>`.
   Ids match `^[a-z][a-z0-9-]{1,30}$`; `iimp/host/all/none/common/stock/settings`
   are reserved.
2. **Stay inside your payload**: every file of the module lives in the payload
   dir (installed as `$II/mod/<id>/`). Never hand-edit anything else under
   `~/.config/quickshell/ii/`.
3. **Slot entry root types**: `bar.qml` MUST root a visual Item (`BarGroup`
   from `qs.modules.ii.bar` gives the standard pill look); `main.qml` MUST root
   `Scope`, `PanelWindow`, or `LazyLoader`.
4. **No singletons**: `pragma Singleton` is forbidden (unregistrable under
   `mod/`). Instantiate a logic object in the entry component and pass the
   instance down (see `modules/network-traffic/TrafficLogic.qml`).
5. **No `import qs.mod.*`**: your own siblings resolve implicitly; other
   modules' QML is not importable in protocolVersion 1.
6. **Own config file only**: persist options via the ConfigLoader pattern to
   `~/.config/illogical-impulse/modules/<id>.json`. NEVER write to the shell's
   `config.json` (its adapter erases undeclared keys).
7. **Probe every stock API**: each stock type/file you use beyond the baseline
   (`Config`, `Appearance`, `Directories`, `Translation`, `modules/common`
   widgets/functions) needs a `compat.probes` entry. Run `iimod suggest <dir>`
   to derive candidates, then review — suggestions are heuristics.
8. **Declare capabilities honestly**: `exec` (Process/execDetached/dispatch),
   `network` (XMLHttpRequest/Socket), `filesystem-write` (writes outside your
   config file), `dbus`. Undeclared-but-used fails validation; over-declaring
   is allowed.
9. **Tier A first**: patches to stock files are a last resort, only when no
   slot can express the feature. If you must (Tier B): insert-only ops,
   literal single-line anchors ≥10 chars chosen from STOCK text (never from
   another module's insertions), content ≤200 lines, never a whole-file
   replacement, `.qml` targets only.
10. **Strict semver**: breaking config-schema or behavior changes bump MAJOR;
    new features MINOR; fixes PATCH. Update `compat.testedOn` when you retest.
11. **Filename hygiene**: no `.qml` basename may equal a stock file under
    `services/` or `modules/common/**` (QML shadowing breaks the shell —
    validation enforces this against the live tree).
12. **Translations**: user-visible strings go through `Translation.tr("English
    source")` with dicts in `translations/<locale>.json` (`en_US` implicit,
    add `zh_TW` at minimum for this community).

## Release checklist (run ALL, in order, before sharing)

```
iimod validate <dir>     # manifest, layout, lint — must exit 0
iimod suggest <dir>      # every suggestion either declared or consciously rejected
iimod check <dir>        # probes/deps/anchors vs your machine — must exit 0
iimod install <dir>      # on your own machine
qs -c ii ipc --any-display call iimp ping   # host alive
# watch the shell: widget renders, no ERROR/TypeError in `qs log`
# toggle off/on in Settings → Modules
iimod uninstall <id> && iimod verify        # must end "all intact"
iimod install <dir> && iimod pack <dir>     # ship the .iimod + its sha256
```

## Never

- `pkill`/`killall` in module code or docs (self-match hazard; reloads go
  through `Quickshell.reload` or the iimp IPC).
- Embedding copies of stock files in your payload.
- Editing the registry (`~/.local/share/iimp/`) by hand.

## 社群中文補充 (zh-TW)

- 術語：模塊=module、插槽=slot、探針=probe、圍欄=fence、母本庫=store。
- 三個血淚教訓（規則 4/6/11 的由來）：檔名撞 stock 單例會讓整個 shell 起不來
  （"Composite Singleton Type X is not creatable"）；shell 的 config.json 會
  自動剝掉未宣告的 key；整檔替換會把過時的上游程式碼一起凍進你的模塊。
- `name`/`description` 記得放 `zh_TW` key；manifest 的欄位名本身保持英文。
- dots 更新後模塊會被清掉是**正常的**——使用者跑 `iimod reapply` 即可復原，
  你不需要（也不准）為此做任何 hack。
