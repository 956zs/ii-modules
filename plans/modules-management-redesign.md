# Modules Management Redesign

## Status

Requirements and design gate. Product implementation has not started.

## Confirmed Direction

- Keep the visual language native to end-4 Quickshell.
- Reuse `Appearance` colors, typography, rounding, Material Symbols, ripple controls, and animation factories.
- Borrow information architecture and interaction patterns from mainstream plugin managers, not their visual skins.
- Treat this as a structural redesign, not a card styling pass.

## Problems To Solve

1. The page title and module names do not establish a strong scan hierarchy.
2. Full manifest descriptions turn every row into a paragraph and hide state and actions.
3. Version, Tier B risk, placement, settings, busy state, and enablement compete in one horizontal row.
4. Settings fragments expand inside the list, making list position and page height unstable.
5. The fixed 600 px content width wastes the available settings window.
6. There is no search, state filter, result count, selected state, or useful no-results state.
7. Icon-only settings actions are ambiguous and unavailable modules are not explained clearly enough.

## Reference Patterns

Use the common structure found in VS Code Extensions, JetBrains Plugins, Obsidian Community Plugins, and desktop add-on managers:

- A prominent page header plus inventory/status count.
- Persistent search and simple status filters.
- Compact list rows optimized for scanning.
- Selection opens a stable detail surface instead of expanding the list row.
- Enable/disable remains available from the list and detail surface.
- Long descriptions, warnings, placement, and module-owned configuration belong in detail.
- Empty and no-result states include a recovery action.

Do not copy marketplace visual branding, star/download metrics, promotional artwork, category taxonomies, or install flows that the local installed-only data model cannot support.

## Information Architecture

### Header

- Large title: `Modules` using the end-4 title family and a size clearly above section labels.
- Supporting line: installed and enabled counts, for example `8 installed · 7 enabled`.
- Search field with leading `search` symbol and a trailing clear action when non-empty.
- Filter chips/segmented buttons: `All`, `Enabled`, `Disabled`, `Needs attention`.

### Wide Layout

Use the available content width as a list/detail workspace.

```text
Modules                                  8 installed · 7 enabled
[ Search modules...                                  x ]
[ All 8 ] [ Enabled 7 ] [ Disabled 1 ] [ Attention 0 ]

+-------------------------------+  +-------------------------------+
| selected Module row       ON  |  | Module name              ON   |
| one-line summary · v1.5.1     |  | v1.5.1 · Bar · Safe           |
|                               |  |                               |
| Module row                ON  |  | Full localized description    |
| one-line summary · v3.4.7     |  | Status / patch warning         |
|                               |  | Bar placement                  |
| Module row               OFF  |  | Module settings fragment       |
+-------------------------------+  +-------------------------------+
```

- Left pane: approximately 38%, with a practical minimum around 280 px.
- Right pane: remaining width, with its own stable content flow.
- Selecting a row changes only the detail pane; list scroll position stays intact.
- First visible result is selected initially. Selection follows filtering safely.

### Narrow Layout

- List occupies the page initially.
- Selecting a row enters a detail view in the same content surface.
- A top back button with `arrow_back` and the module name returns to the preserved list/search/filter/scroll state.
- The enable switch remains visible in both list and detail.

## Module Row

- Stable compact height; no inline settings expansion.
- Leading semantic icon derived from slots:
  - `bar` -> `toolbar`
  - `window` -> `web_asset`
  - both -> `dashboard_customize`
- Primary line: localized module name, DemiBold, larger than metadata.
- Secondary line: localized description elided to one line on wide layout and at most two lines on narrow layout.
- Metadata line: version plus concise slot label.
- Status is conveyed by text/icon in addition to color.
- Tier B is not rendered as the long phrase `patches stock files` in every row. Use a compact warning symbol and `Patched` label; explain it fully in detail.
- Entire row is selectable with hover/ripple feedback. The switch remains an independent target and must not also select/trigger the row accidentally.
- Busy state replaces or overlays the switch with progress feedback and prevents duplicate operations.

## Detail View

1. Header: icon, localized name, version, enable switch.
2. Status strip only when needed:
   - incompatible
   - blocked by dependency
   - operation error
   - Tier B stock-file modification warning
3. Full localized description.
4. Host settings:
   - vertical bar placement, only for `bar` modules
5. Module settings:
   - lazy-loaded existing settings fragment
   - an explicit `Settings` section label
   - if no settings entry exists, show a quiet `No configurable options` state rather than a gear icon
6. Technical metadata kept compact: module id and slots. No new manifest fields are required for v1.

## Visual System

- Colors: only existing `Appearance.colors` and `Appearance.m3colors` tokens.
- Typography: title family for the page/detail title; main family for rows and controls.
- Shape: existing `Appearance.rounding.small/normal/full`; no foreign card or web-dashboard treatment.
- Icons: existing Material Symbols only.
- Motion: existing `Appearance.animation.elementMoveFast`, `elementMoveSmall`, `elementResize`, and page-enter factories.
- Avoid nested decorative cards. The workspace may use two surface regions; repeated module rows are list items, not cards inside cards.
- No gradients, brand illustrations, marketplace artwork, or new palette.

## Data And Behavior Contract

The current projection already provides all required fields:

- `id`, localized `name`, localized `description`
- `version`, `slots`, `state`, `settings`, `tierB`

Keep `iimod enable/disable` as the state authority. Preserve:

- PATH fallback to `~/.local/bin/iimod`
- index projection reload as final synchronization
- failure snap-back
- lazy settings loading
- module settings fragment state while the selected detail remains mounted
- host-owned vertical bar placement storage

Filtering must match localized name, id, and localized description case-insensitively. Sorting remains registry order for v1 so the redesign does not silently redefine module priority.

## Empty States

- No installed modules: prominent extension icon, `No modules installed`, and the concise install command.
- No search/filter results: `No matching modules`, with a visible clear-search/reset-filter action.
- Invalid index: same empty shell plus a non-sensitive read failure message; do not expose internal stack traces.

## Accessibility And Interaction

- Minimum 40 px pointer target for list actions; use 44 px where layout permits.
- Every icon-only action has a tooltip/accessibility name where supported by the host controls.
- State never relies on color alone.
- Keyboard focus remains visible; Escape clears search first, then returns from narrow detail.
- Search updates immediately without requiring Enter.
- No hover transform or geometry shift.
- Text elides or wraps within fixed bounds and never overlaps switches or metadata.

## Acceptance Criteria

- At 1100x750, the content uses the available pane instead of remaining a centered 600 px column.
- At least six normal module rows are scannable without paragraph blocks or expanded settings.
- Page title is visually stronger than module names; module names are stronger than metadata.
- Every module can be found by localized name or id.
- Filters correctly separate enabled, disabled, and incompatible/blocked modules.
- Selecting a module never changes list height or list scroll position.
- Long descriptions are capped in the list and fully readable in detail.
- Enable/disable success, busy, and failure behavior preserve current authority and snap-back semantics.
- Tier B risk is concise in the list and explicit in detail.
- Bar placement and all existing module settings remain operational.
- Wide and minimum-size settings windows have no horizontal overflow, clipped controls, or overlapping text.
- QML parses cleanly; Rust/index projection tests pass; focused UI contract tests cover filtering, selection, and removal of inline settings expansion.
- Real settings app is launched and visually checked at wide and minimum supported sizes before completion.
