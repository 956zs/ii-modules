# Module development gotchas

Observed runtime pitfalls that repeatedly cost debugging time when building
first-party modules. Every module author (human or agent) should scan this
list before writing or testing a module. Rules that are protocol requirements
live in `spec/SPEC-1.0.md` and the author skill; this file is for behavior the
protocol cannot check for you.

## QML / Quickshell runtime

- `Translation` is a singleton in `qs.services`, not `qs.modules.common`.
  Omitting `import qs.services` where `Translation.tr` is used fails at
  runtime with `ReferenceError: Translation is not defined`. Two modules
  (screentime, memory_center) independently hit this.
- A `Canvas` inside a `PanelWindow` created with `visible: false` never paints
  when the window later maps. Add
  `onAvailableChanged: if (available) requestPaint()` to every such Canvas.
- Bar-slot entries are instantiated once per bar/monitor. Window-slot
  `main.qml` loads exactly once. Any accounting or otherwise stateful owner
  must live in the window slot, or it double-counts on multi-monitor setups.
- QML FINAL property collisions fail the whole module at load with
  `Cannot override FINAL property`. Known traps: `property var top` and
  `property bool bottom` on an `Item` (every anchor line name: `top`,
  `bottom`, `left`, `right`, `horizontalCenter`, `verticalCenter`,
  `baseline`), `property string icon` on a Controls `Button`. Pick
  non-builtin names (`topProcs`, `barAtBottom`, `iconName`). A host asset
  failing this way breaks the whole shell reload, not just one module.
- Inside a `LazyLoader { component: ... }`, a binding whose property name
  equals an outer id (`mem: mem`) resolves to the property itself and stays
  permanently undefined, even though the same pattern works for direct
  children. The same happens for a property declared on a `StyledPopup`
  (itself a LazyLoader) root and bound at the use site (`osu: osu` on
  `OsuPopup` resolved to the popup's own property, so the popup never
  rendered). Give ids different names from the properties they feed
  (`memInfo`, `procTop`, `reader: osu`).
- Never declare `property var` inside a `JsonAdapter`/`JsonObject`:
  Quickshell's deserializer segfaults writing a JSON object into it.
  Represent maps as a JSON string property and `JSON.parse` at the reader.
- `StyledPopup` content loads lazily on first hover, so QML errors inside it
  never appear at module load. Always hover-open every popup once after
  editing its content.
- Quickshell 0.2.1 emits `runningChanged` but no `exited` on
  `QProcess::FailedToStart`. A fallback chain that waits for `exited` hangs;
  guard with a zero-delay check on the failed-to-start path (see
  `modules/network_traffic`).
- Material Symbols coverage varies by installed font build. Verify a glyph
  name exists (for example with fontTools against the installed variable
  font) before shipping an icon name; missing glyphs render as tofu.
- Bar pages (`iimp.barPagesJson`, host generation 4) keep every page's
  modules instantiated; a module on a non-current page is fully visible in
  QML terms but has `opacity: 0` and `enabled: false` on its page row, and
  once its fade-out ends the row is translated out of the bar window. Do
  not key behaviour on `visible` to detect "my page is shown"; hover and
  click simply do not arrive while the page is away. The slot reserves the
  width of the widest page, so a module that grows on page 2 widens the slot
  on page 1 as well.
- `enabled: false` does not stop hover in Qt 6: hover is delivered by
  geometry and `MouseArea.hoverEnabled` is independent of `Item.enabled`, so
  a faded-out item still raises `containsMouse` and any popup bound to it.
  Hide hoverable content by moving it out of the window (a `Translate`
  transform keeps anchors, implicit sizes and effective visibility intact)
  or by `visible: false` when the effective-visibility trap does not apply.
- Bar order (`iimp.barOrderJson`, host generation 4) is a JSON array of ids;
  `enabledBar` itself stays alphabetical (the host re-sorts it on every
  enable/disable), so never read `enabledBar` as the display order. Listed
  ids render first, unlisted ones follow alphabetically, and the horizontal
  bar's first id is the rightmost one.

## IIMP / iimod workflow

- `iimod` serializes mutating transactions with a global lock. Concurrent
  agents get `another iimod is running`; assign exactly one live mutation
  owner per session and retry read-only work with backoff. If the message
  reports `pid 1`, that is the permanent legacy fence: upgrade the binary,
  never delete `~/.local/share/iimp/lock`.
- `iimod pack` requires `--origin <url>` or an explicit `--no-origin`, and
  the output flag is `--out <path>`.
- Always run mutating transactions with the binary built from the current
  worktree when host assets changed; a stale PATH binary can silently
  downgrade embedded host assets (mitigated by host generations in
  `iimod` >= 1.2.0, but the habit still applies to older installs).

## Toolchain

- `/usr/bin/qmlformat` may be the Qt 5 build (reports version 1.0) that
  false-fails on modern QML (`?.`, `??`). Use the Qt 6 binary at
  `/usr/lib/qt6/bin/qmlformat` for parse checks.
- Quickshell's runtime log ring
  (`/run/user/<uid>/quickshell/by-id/<id>/log.log`) is encoder-versioned;
  a `qs` binary newer or older than the one that started the instance
  cannot decode it, and the shell's stdout/stderr usually go to /dev/null.
  When the log is unreadable, verify behaviorally: `iimp ping`, IPC panel
  toggles, and `iimod verify`.

## Live testing

- Popup and lazy-loaded surfaces need an interaction (hover/click) before
  their errors appear in the shell log; a clean log at load proves nothing
  about popup content.
- When driving the pointer with automation tools while a user is at the
  machine, perform move → verify position → click inside one shell
  invocation; a click issued in a separate command races the user's mouse.
- Synthetic pointer tools may apply acceleration or coordinate scaling.
  Position with a feedback loop against `hyprctl cursorpos` instead of
  trusting requested coordinates.
- Hyprland 0.56+ takes Lua dispatchers: `hyprctl dispatch movecursor X Y`
  now fails. Use `hyprctl dispatch 'hl.dsp.cursor.move({x=X,y=Y})'`
  (layout coordinates, exact, no acceleration), verify with
  `hyprctl cursorpos`, then `ydotool click 0xC0`.
- Reading another object's attached properties (`item.Layout.fillWidth`)
  needs that attached type imported in the reading file
  (`import QtQuick.Layouts`); without it `item.Layout` is `undefined`.
