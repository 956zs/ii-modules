# IIMP — illogical-impulse Module Protocol

**Specification 1.0 · protocolVersion 1 · Status: Normative**

IIMP defines how community modules for the end-4/dots-hyprland "illogical-impulse"
Quickshell configuration (the *shell*, rooted at `~/.config/quickshell/ii`, hereafter
`$II`) are structured, versioned, compatibility-checked, installed, and removed.
The reference implementation is the `iimod` CLI. The key words MUST, MUST NOT,
SHOULD, and MAY are to be interpreted as in RFC 2119.

Design axioms, in priority order:

1. **Never corrupt the shell.** Every mutation is transactional; a failed operation
   leaves the tree byte-identical to its pre-operation state.
2. **Determinism.** The bytes on disk are a pure function of (stock tree, set of
   installed modules). Install order MUST NOT affect the result.
3. **Refusal over guessing.** When compatibility cannot be proven, the operation
   fails with a diagnostic. There is no `--force` for probe or anchor failures.
4. **Honesty about trust.** Modules run arbitrary QML in the user's session.
   Capabilities are informed consent, not a sandbox (§10).

---

## 1. Definitions

| Term | Meaning |
|---|---|
| shell | The Quickshell config tree at `$II` |
| stock file | A file shipped by dots-hyprland inside `$II`, outside `$II/mod/` |
| module | A directory `$II/mod/<id>/` plus its manifest, installed by iimod |
| host | IIMP's own runtime (`$II/mod/iimp/` + its fenced host patches; targets absent from older stock trees are skipped), owned by iimod |
| slot | A predefined extension point: `bar` or `window` |
| Tier A module | A module with an empty `patches` array (slot-only, zero stock modification) |
| Tier B module | A module with a non-empty `patches` array (modifies stock files) |
| probe | A declarative compatibility assertion evaluated against fence-stripped stock text |
| fence | A comment-delimited region marking IIMP-owned content inside a stock file |
| wipe zone | Everything under `~/.config/quickshell/` — deleted/reset by dots updates |
| state root | `~/.local/share/iimp/` — authoritative state, outside the wipe zone |

The shell has **no version identity** (no git metadata, no version file). Therefore
compatibility in IIMP is proven by **feature probes**, never by version comparison
against the shell. `compat.testedOn` is a heuristic record only and MUST NOT gate
any operation.

## 2. Module identity and layout

### 2.1 id

- Regex: `^[a-z][a-z0-9_]{1,30}$`; additionally MUST NOT end with `_` or contain `__`.
- Rationale: the id doubles as a QML module URI segment (`import qs.mod.<id>`,
  §2.2), and QML URIs forbid hyphens. Underscores are the separator.
- Reserved ids (installation MUST be refused): `iimp`, `host`, `all`, `none`,
  `common`, `stock`, `settings`.
- The payload directory name and (for packages) the archive's single top-level
  directory MUST equal `id`.

### 2.2 Payload layout

```
<id>/
  module.json                 # manifest (§3) — REQUIRED
  bar.qml                     # bar slot entry (if slots contains "bar")
  main.qml                    # window slot entry (if slots contains "window")
  settings.qml                # optional settings fragment (Item root)
  translations/<locale>.json  # optional flat key→string dicts
  i18n.sources.json           # optional development metadata; no runtime role
  README.md                   # RECOMMENDED
  ...                         # any further QML/JS/assets, free-form
```

Rules:

- All module files live under the payload directory. There is no destination
  mapping: the payload tree **is** the installed tree at `$II/mod/<id>/`.
- A `bar.qml` entry MUST root a visual Item (it is loaded by a QtQuick `Loader`).
- A `main.qml` entry MUST root `Scope`, `PanelWindow`, or `LazyLoader` (it is
  instantiated via `Qt.createComponent`; it owns its own windows).
- `.qml` file basenames MUST NOT equal the basename of any file under
  `$II/services/` or `$II/modules/common/**` (QML same-directory type resolution
  would shadow or collide with stock singletons/types; see §12 lesson 1).
- `pragma Singleton` MUST NOT be used anywhere in a module; modules instantiate
  a plain logic object in their entry component and pass the instance down.
- User-visible runtime strings SHOULD use
  `Translation.tr("English source")`. A missing dictionary or key MUST fall back
  to that English source argument. `translations/<locale>.json` remains optional
  at the protocol layer so existing protocolVersion 1 payloads stay compatible.
- `i18n.sources.json`, when present, describes finite nonliteral source sets for
  development tools. It is not a manifest field, is ignored by runtime lookup,
  and adds no protocolVersion 1 installation behavior.
- **Sibling types require an explicit self-import.** Files loaded by path
  (every slot entry) get NO implicit same-directory type resolution under
  Quickshell's URL interceptor (verified empirically; stock path-loaded pages
  also use only URI imports). A file that references sibling components MUST
  declare `import qs.mod.<own-id>`. (Resolution works because the host keeps a
  generated, statically-compiled `ModuleImports.qml` registering every installed
  module directory — QML only generates directory-modules during static
  compilation. iimod maintains it; authors just write the import.) Importing ANY
  OTHER module's directory is forbidden. Cross-module QML sharing is not supported in protocolVersion 1;
  `requires.modules` expresses lifecycle dependency, not QML imports.

### 2.3 Guaranteed baseline (no probe required)

Modules MAY rely on these without declaring probes: `qs.modules.common`
(`Config`, `Appearance`, `Directories`), `qs.modules.common.widgets`,
`qs.modules.common.functions`, `qs.services.Translation`. Every OTHER stock type,
singleton, or file a module consumes (e.g. `qs.modules.ii.bar.StyledPopup`,
`qs.services.Network`) MUST be covered by a probe (§4).

### 2.4 Per-module configuration

Modules MUST NOT write to `~/.config/illogical-impulse/config.json` (the shell's
JsonAdapter erases undeclared keys on write — §12 lesson 2). Persistent module
options live in `~/.config/illogical-impulse/modules/<id>.json`, implemented with
the FileView + JsonAdapter pattern (watchChanges, debounced write, create-on-missing).
The `iimod init` scaffold ships a `ConfigLoader.qml` template.

## 3. Manifest — `module.json`

Encoding: UTF-8 JSON, LF line endings. Unknown fields are a **validation error**
(this is deliberate: schema strictness is enforced by rejection, and any additive
field change requires a protocolVersion bump — §11).

| Field | Type | Req | Rules |
|---|---|---|---|
| `protocolVersion` | integer | ✔ | Supported range of the tool (this spec: exactly `1`); out of range → exit 10 |
| `id` | string | ✔ | §2.1 |
| `name` | object locale→string | ✔ | `en_US` key required, ≤ 40 chars |
| `description` | object locale→string | ✔ | `en_US` key required, non-empty |
| `version` | string | ✔ | Strict semver `X.Y.Z[-pre]`; prerelease installs emit a warning |
| `authors` | string[] | ✔ | Non-empty |
| `license` | string | ✔ | SPDX-style token recommended (warn otherwise) |
| `homepage` | string | — | Must match `^https?://` if present |
| `slots` | string[] | ✔ | Non-empty, unique, values ∈ {`bar`, `window`} |
| `entries` | object | — | Keys ∈ {`bar`,`window`,`settings`}; values: relative `.qml` paths within the payload, no `..`; defaults: `bar.qml` / `main.qml`; an entry file MUST exist for every declared slot |
| `compat` | object | ✔ | See §4 |
| `requires` | object | — | See §5 |
| `conflicts` | string[] | — | Module ids; enforced in both directions at install |
| `capabilities` | string[] | ✔ (may be `[]`) | Values ∈ {`exec`, `network`, `filesystem-write`, `dbus`}; cross-checked by lint (§6) |
| `patches` | Patch[] | — | Non-empty ⇒ Tier B (§7) |

Locale keys match `^[a-z]{2,3}_[A-Z]{2}$`.

`integrity.json` is NOT part of the manifest. It is generated by `iimod pack`
next to the manifest inside the package: `{"specVersion": 1, "manifestSha256":
"...", "files": {"<relpath>": "<sha256>", ...}}` covering every payload file.
It may carry an optional `origin` (an update-index URL embedded by
`pack --origin`); consumers MUST ignore unknown integrity fields so the
sidecar can grow without breaking older packages or newer tools.

## 4. Compatibility probes

```json
"compat": {
  "probes": [
    {"type": "file-exists",   "path": "modules/ii/bar/StyledPopup.qml",
     "reason": "popup API used by the bar entry"},
    {"type": "file-contains", "path": "services/Network.qml",
     "pattern": "property string materialSymbol",
     "reason": "network type icon consumed in popup header"}
  ],
  "testedOn": {"dotsCommit": "446504ad42", "qsVersion": "0.2.1"}
}
```

- `path` is relative to `$II`, MUST NOT contain `..`, MUST NOT point under `mod/`.
- `pattern` is a **literal substring** (never a regex — §12 lesson 3), minimum
  6 characters, required iff `type == "file-contains"`.
- `reason` is required and non-empty; tools echo it in failure diagnostics.
- Evaluation: probes are checked against **fence-stripped** file content (§7.2),
  so a probe can never be satisfied by another module's inserted text.
- Any probe failure at `check`, `install`, or `reapply` time is **absolute**
  (exit 4). There is no bypass flag. `reapply` marks the module `incompatible`,
  excludes its patches, force-disables it, and continues with other modules.

## 5. Dependencies and conflicts

```json
"requires": {
  "modules": [{"id": "traffic_core", "versionReq": ">=1.2, <2"}],
  "system":  [{"bin": "jq", "hint": "sudo pacman -S jq"}]
}
```

- `versionReq` uses Rust `semver::VersionReq` grammar (`^1.2`, `~1.4.3`,
  `>=1.4, <2`, exact `=1.2.3`).
- Install requires every listed module to be **already installed** with a
  satisfying version (exit 5 otherwise). This also structurally prevents cycles.
- `enable A` auto-enables A's installed dependency closure; `disable A`
  auto-disables A's transitive dependents (both reported in output).
- A disabled module contributes **neither slots nor patches**: flipping a
  Tier B module's state recomposes its target files (the same
  `compose(strip(s), P)` with the module's patches excluded from `P` — this
  is the same exclusion §9 already applies to `incompatible` modules).
- `uninstall A` with installed dependents is refused (exit 5); `--cascade`
  removes dependents in reverse topological order after listing them.
- `system` entries are binaries that must resolve on `$PATH` (`bin` is a
  basename, no `/`).
- Conflicts: installation is refused (exit 5) if the new module declares an
  installed module in `conflicts`, or any installed module declares the new id.

## 6. Capabilities and lint

`capabilities` is a mandatory honest declaration of what the module's code does:

| Capability | Meaning | Lint detectors (heuristic, documented) |
|---|---|---|
| `exec` | Spawns processes | `Process {`, `execDetached(`, `Hyprland.dispatch(` |
| `network` | Network I/O | `XMLHttpRequest`, `WebSocket`, `Socket` |
| `filesystem-write` | Writes files outside its own config | `.setText(`, `writeAdapter(` — except the blessed ConfigLoader pattern targeting `modules/<id>.json` |
| `dbus` | D-Bus access | `DBus` |

Lint verdicts: **used but undeclared → validation failure (exit 3)**; declared
but not detected → warning (over-declaration is always permitted). Reading files
(FileView without write) requires no capability. The lint is a grep-class
heuristic and is documented as such; it raises the honesty bar, it does not
sandbox (§10).

## 7. Tier B: structured patches

### 7.1 Patch operations

```json
"patches": [
  {"file": "modules/ii/bar/BarContent.qml",
   "op": "insert-before",
   "anchor": "            // Weather",
   "content": "            MyThing {}\n"}
]
```

- `file`: relative to `$II`; MUST be a regular (non-symlink) stock `.qml` file;
  MUST NOT be under `mod/`; no `..`, no absolute paths.
- `op` ∈ {`insert-after`, `insert-before`}. protocolVersion 1 has **no** replace,
  delete, or whole-file operations (§12 lesson 4).
- `anchor`: literal substring, ≥ 10 chars, single line. After fence-stripping,
  exactly **one** line of the target must contain it: zero matches → exit 8
  (incompatible), two or more → exit 8 (ambiguous — pick a more specific anchor).
- `content`: UTF-8, LF, ≤ 200 lines, MUST NOT contain lines matching the fence
  marker grammar.
- Installing any Tier B module requires the explicit `--allow-patches` flag
  (exit 9 otherwise). This is the hard gate; agent workflows add a mandatory
  human-consent review on top (skills).

### 7.2 Fence grammar

Every applied patch is wrapped in fences:

```
// >>> iimp <id>/<n> v<version> >>>
...content...
// <<< iimp <id>/<n> <<<
```

`<id>` = module id, charset `[a-z0-9_-]+` (`host` for host-owned fences); `<n>` = 0-based patch index
within that module; `<version>` = module version at application time
(informational). Blocks are contiguous, non-nested, and properly paired.
`strip(text)` removes all well-formed blocks. Any pairing/grammar violation puts
the file in the `fence-broken` state (§9).

### 7.3 Recomposition engine (normative laws)

The engine never edits incrementally. For every touched stock file:

```
composed = compose(strip(current_bytes), P)
```

where `P` = the ordered set of all surviving patches targeting that file across
all installed modules, sorted by `(module id lexicographic, patch index)` for
identical anchors. Laws (property-tested by the reference implementation):

1. `strip(compose(s, P)) == s` for all stock text `s` and valid patch sets `P`.
2. `compose` is a pure function of `(s, P)` — install order cannot affect bytes.
3. Anchors resolve exclusively against `strip`ped text — a patch can neither
   target nor collide with another module's inserted content.

Every mutation (install, uninstall, repair, reapply) rewrites all fenced regions
of each touched file from scratch via this function.

## 8. Filesystem contract

### 8.1 Writable roots (closed set)

An IIMP tool may write ONLY to:

1. `$II/mod/<id>/` (module payloads) and `$II/mod/iimp/` (host)
2. Declared `patches[].file` targets (via recomposition only)
3. `~/.config/illogical-impulse/modules/` (`index.json` projection, per-module configs)
4. `~/.config/illogical-impulse/translations/<locale>.json` (key merge, §8.3)
5. `~/.local/share/iimp/**` (state root)

Everything else is out of bounds. Package extraction rejects: `..` components,
absolute paths, symlinks/hardlinks, special files, non-UTF-8 names, setuid bits,
and > 20 MiB unpacked (overridable with `--max-size`).

### 8.2 State root layout

```
~/.local/share/iimp/
  registry.json       # AUTHORITATIVE: schemaVersion, hostVersion, modules[]
                      #   {id, version, state, slots, files{path:sha256},
                      #    patchRecords, translationKeys{locale:[keys]}}
  lock                # single-writer lock (O_EXCL, pid, stale detection)
  journal.json        # in-flight transaction journal
  store/<id>/<ver>/   # pristine module payloads (reapply source)
  pristine/<relpath>  # first-touch snapshots of patched stock files
  backups/<ts>/       # pre-mutation copies of every file a transaction touches
  tmp/                # extraction staging
```

Registry writes are atomic (temp + rename) and keep one `.bak`. A corrupt
registry blocks all mutating commands (exit 7); `doctor --rebuild-registry`
reconstructs best-effort from store + filesystem.

The shell-side enabled state (`Config.options.iimp.enabledBar/enabledWindow`) is
a **projection** of the registry, rebuilt by `reapply` and reconciled by
`doctor`. When the shell runs, enable/disable flows through the host IPC
(`qs -c ii ipc --any-display call iimp setEnabled ...`) so the shell is the single
writer of `config.json`; direct file editing is a fallback used only when the
shell is down, with a write→verify loop.

### 8.3 Translations

Module dicts merge into `~/.config/illogical-impulse/translations/<locale>.json`
at install (the shell's generated-dict lookup; repo dict wins collisions). Module
code passes an English source to `Translation.tr`; if the active dictionary has
no matching entry, the shell returns that source unchanged.

Registry `translationKeys` entries are references, not exclusive ownership.
Every installed module whose stored dictionary contributes the selected value is
recorded as a reference. Same-value sharers therefore survive uninstall in any
order until the last contributor is removed. Different-value contributors retain
deterministic first-value-wins behavior; a present unowned value or a value that
differs from all previously managed contributors is treated as a user entry/edit
and is never overwritten or removed. Uninstall and reapply reconcile surviving
store payloads, and a key is removed only when no contributor survives and its
current value still equals the removed managed value. A shell reload is required
for new keys to take effect (the reader does not watch the file).

### 8.4 Reference authoring checks (non-normative)

The reference CLI provides development-time commands without changing the
manifest schema or runtime protocol:

```text
iimod i18n extract <SOURCE>
iimod i18n extract --all
iimod i18n check <SOURCE> [--locale <LOCALE>...] [--deny-orphans]
iimod i18n check --all [--locale <LOCALE>...] [--deny-orphans]
```

`SOURCE` accepts a payload directory or package. Extraction is read-only and
scans payload QML/JS plus QML in `module.json` patch content. A payload-root
`i18n.sources.json` may declare exact finite sets for otherwise nonliteral calls;
undeclared, ambiguous, duplicate, or stale declarations fail extraction and
checking.

Standalone checks default to `zh_TW`, the portable authoring minimum. Repository
checks default to `zh_TW` and `zh_CN`; repeated `--locale` options replace those
defaults. This repository runs `--all --deny-orphans`, making both first-party
catalogs exact. These locale and exact-set requirements are reference-tool and
repository authoring policy, not new protocolVersion 1 manifest requirements.

The checker requires exact nonempty English keys, canonical `%1` through `%99`
placeholders with contiguous indices, matching immediate `.arg()` counts, and
the same placeholder multiset in each translation. `%n` is rejected because the
runtime has no plural API. Dictionaries must be string-to-string objects in
Unicode-codepoint key order, two-space JSON, and one final newline. Missing or
malformed entries fail; orphans warn unless denied. Repository checking allows
same-value locale/source sharing and rejects different-value conflicts.

## 9. Lifecycle states and `verify`

| State | Detection | Remediation |
|---|---|---|
| `intact` | module files == store hashes; each patched file: bytes == compose(pristine, patch set) | — |
| `module-modified` | module file ≠ store hash | `iimod repair <id>` restores from store |
| `stock-drifted` | strip(current) ≠ pristine snapshot; fences intact | user/upstream edit → `iimod reapply` re-anchors + re-snapshots |
| `fence-broken` | fence grammar violation | `iimod repair` (recompose) |
| `missing` | expected file absent while host sentinel present | `iimod repair` |
| `wiped` | host sentinel absent but registry non-empty (dots update ran) | `iimod reapply` |
| `incompatible` | probe/anchor failed at last reapply | wait for module update; module stays disabled |

Every iimod invocation checks for the wiped state and prints a prominent
`WIPED — run: iimod reapply` banner. **After every dots-hyprland update, run
`iimod reapply`.** It is idempotent and safe to run at any time.

## 10. Threat model (honest)

Installing a module executes third-party QML in your graphical session with your
user's privileges. It can read your files, run programs (`exec`), and reach the
network. IIMP's protections — capability declarations, static lint, Tier B hard
gate, fenced determinism — provide *informed consent and reversibility*, **not
confinement**. Review code you install, or have your agent walk the
`ii-module-manage` review procedure and report to you before consenting.
Prebuilt `iimod` binaries are published with sha256 checksums; building from
source is two commands and recommended for the cautious.

## 11. Protocol evolution

- `protocolVersion` is an integer. Each tool release declares a supported
  contiguous range (this spec's reference tool: `[1, 1]`). Out-of-range
  manifests fail with exit 10 before any other diagnostic.
- Because unknown manifest fields are rejected, **any** field addition requires
  a protocolVersion bump. SPEC 1.x editions may only clarify wording; anything
  that changes a validation outcome or on-disk behavior is SPEC 2.0 with
  protocolVersion 2.
- The registry has an independent `schemaVersion`; newer tools migrate it
  forward; an older tool meeting a newer schema refuses to write (exit 10).

## 12. Codified lessons (why these rules exist)

1. **Type-name collision**: a module QML basename equal to a stock singleton
   (`services/NetworkTraffic.qml`) makes the shell fail with
   "Composite Singleton Type X is not creatable". Hence the basename deny-list.
2. **JsonAdapter schema erasure**: the shell's config adapter silently drops
   undeclared keys from `config.json` on its next write. Hence declared registry
   keys in the host patch, and per-module config files elsewhere.
3. **Regex anchors rot silently**: upstream refactors break regexes in
   surprising ways. Literal substrings fail loudly and predictably; uniqueness
   is validated at apply time.
4. **Full-file replacement embeds stale upstream code**: replacing a stock file
   freezes a foreign snapshot of everything else in it. Insert-only patches keep
   upstream's code upstream's.
5. **`pkill -f` self-matches**: process management by pattern can kill the
   invoking shell. IIMP tooling never uses pkill; reloads go through IPC or
   file-watch triggers.
6. **The wipe zone is total**: dots updates `rsync --delete` the whole shell.
   Everything IIMP needs to survive lives in the state root; everything inside
   `$II` is reproducible from it.

## 13. Exit codes (stable API)

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | internal error |
| 2 | usage error |
| 3 | validation failed (manifest, lint, layout, injection) |
| 4 | compatibility probe failed |
| 5 | dependency/conflict unsatisfied |
| 6 | integrity mismatch |
| 7 | state error (lock held, wiped pending, corrupt registry, cycle) |
| 8 | patch anchor failed or ambiguous |
| 9 | Tier B without `--allow-patches` |
| 10 | protocolVersion / registry schema unsupported |
