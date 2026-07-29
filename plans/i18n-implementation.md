# Module i18n implementation

## Scope

Retain the existing runtime contract:

- QML/JS calls `Translation.tr("English source")`.
- A payload contributes `translations/<locale>.json` dictionaries.
- `iimod` merges module dictionaries into generated shell dictionaries.
- Missing runtime entries fall back to the English source key.

This phase adds development-time extraction and checking, repairs installed
translation ownership, fills the current first-party catalogs, and makes the
same checks authoritative in validation, CI, and release workflows. It does
not introduce Qt Linguist, TS/QM files, a second runtime, or a manifest schema
change.

## Command contract

Add a nested CLI command:

```text
iimod i18n extract <SOURCE>
iimod i18n extract --all
iimod i18n check <SOURCE> [--locale <LOCALE>...] [--deny-orphans]
iimod i18n check --all [--locale <LOCALE>...] [--deny-orphans]
```

`SOURCE` and `--all` are required and mutually exclusive. A standalone source
accepts a payload directory or `.iimod` package through the existing payload
loader. `--all` discovers the repository root from the current directory and
checks direct `modules/<id>/` children only; module ordering is by manifest id
and directory/manifest id mismatches are errors.

Standalone checks default to `zh_TW`. Repository checks default to `zh_TW` and
`zh_CN`. Repeated `--locale` arguments replace the defaults. Invalid command
shape is clap exit code 2; extraction and catalog validation failures use the
existing validation exit code 3.

`extract` is read-only. Single-source output is a two-space JSON object with a
final newline:

```json
{
  "module": "sample",
  "sources": ["First source", "Second source"]
}
```

`--all` emits `{"modules":{"<id>":[...]}}` with deterministic ordering.

## Source extraction

Implement the scanner in `tools/iimod/src/i18n.rs`, separate from runtime
projection in `translations.rs`. Use a deterministic lexer instead of a
regular-expression-only extractor and do not add a QML parser dependency.

Scan all payload `.qml` and `.js` files in sorted relative-path order, excluding
non-payload directories through normal payload layout validation. Also scan
each `module.json` `patches[i].content` value as an in-memory QML source named
`module.json#patches/<i>/content`.

The scanner must:

- skip line comments, block comments, and strings containing apparent calls;
- recognize `Translation.tr()` across whitespace and line breaks;
- decode single-quoted, double-quoted, and non-interpolated backtick strings;
- balance parentheses, brackets, and braces while finding the complete call;
- count the immediate `.arg(...)` chain after each call;
- reject concatenation, interpolation, identifiers, member expressions, and
  other nonliteral arguments unless an exact dynamic declaration covers them;
- report stable `source:line:column` diagnostics.

The extracted source set is the union of literal calls and declared controlled
dynamic sources.

## Controlled dynamic sources

An optional payload-root `i18n.sources.json` declares finite source sets for
nonliteral calls without changing `module.json` or IIMP protocol schema:

```json
{
  "schemaVersion": 1,
  "declarations": [
    {
      "source": "settings.qml",
      "expression": "modelData.label",
      "sources": ["Click bounce", "Element enter", "Element exit"]
    }
  ]
}
```

Each nonliteral call must match exactly one declaration by source unit and
whitespace-normalized argument expression. Reject unsupported versions,
unknown fields, duplicate declarations, empty/duplicate source keys, unmatched
declarations, and undeclared dynamic calls. Declarations sort by source then
expression; each source list sorts by Unicode codepoint.

`animation_tuner` declares both actual dynamic expressions used by its UI and
the eight labels returned by `MotionMath.tokenCatalog()`.

## Catalog checks

For every extracted or declared English source:

- require a nonempty exact string without leading/trailing whitespace or
  control characters;
- forbid `%n` because the runtime has no plural API;
- accept only canonical numeric placeholders `%1` through `%99`;
- require placeholder indices to be contiguous from `%1` to `%N`;
- require exactly `N` immediate `.arg()` calls at each call site.

For every required locale dictionary:

- require the file and a JSON object containing only string-to-string entries;
- require every extracted source key;
- require nonempty values after trimming and forbid control characters;
- reject explicit placeholder markers `TODO`, `TBD`, `FIXME`, `TRANSLATE`, and
  `UNTRANSLATED`, case-insensitively and with an optional colon suffix;
- preserve the source placeholder multiset exactly while allowing reordering;
- require Unicode-codepoint key order, two-space JSON, and one final newline;
- warn when source and translated value are identical;
- warn on orphan keys by default and fail on them with `--deny-orphans`.

Repository checks group dictionaries by `(locale, source)`. Same-value sharing
is valid. Different values are an error that names every contributing module
and value.

## Translation ownership

Keep registry schema version 2 and the existing `translationKeys` field.
Reinterpret each module's keys as translation references rather than an
exclusive ownership claim. Do not add a second ownership database.

Reconciliation uses dictionaries from installed immutable store payloads, with
an install candidate supplied as an override. Contributor order is
`(installedAtEpoch, moduleId)`.

- If output lacks a key, select the oldest contributor.
- If output equals a contributor value, retain it and record every contributor
  with that same value as a reference.
- Preserve first-value-wins for conflicting contributors; repository checks
  prevent new first-party conflicts.
- If output differs from every previously managed contributor value, treat it
  as a user edit and do not overwrite or remove it.
- A sole-owner upgrade replaces the old value only while output still equals
  the old stored value.
- Uninstall searches all surviving store dictionaries, repairing old registries
  where same-value sharers were not recorded.
- If a survivor supplies the removed value, retain it and record all same-value
  survivors. If only conflicting survivors remain, choose deterministically.
- Remove a key only when no contributor survives and output still equals the
  removed module's value.
- `reapply` performs complete reconciliation and reconstructs reference sets;
  `doctor --rebuild-registry` may continue writing empty sets until reapply.

Install rollback backs up the union of old-module, candidate, and reconciliation
locales, including locales removed during an upgrade.

## Delegation boundary

After feature source strings freeze, an i18n subagent may edit only the target
module's `translations/*.json` and `i18n.sources.json`. It may not change QML,
JS, `module.json`, versions, README files, capabilities, settings schemas, or
tests merely to satisfy the checker. Ambiguous English text or dynamic source
provenance returns to the feature owner.

The repository and portable `ii-module-i18n` skills must remain byte-identical.
Workflow changes also update `AGENTS.md` and both `ii-module-author` skill copies.

## Rollout order

1. Add ownership regressions and reconciliation without changing registry schema.
2. Add scanner, dynamic catalog parser, `extract`, and report-capable `check`.
3. Add `animation_tuner/i18n.sources.json`.
4. Fill missing `zh_TW`/`zh_CN`, normalize the three current conflicts, and
   fix formatting or placeholder errors. Do not delete unconfirmed orphans.
5. Make payload validation enforce structural checks and `zh_TW` completeness,
   returning orphan findings through its warning channel.
6. Add repository-wide CI checking for both first-party locales.
7. After the baseline is exact, enforce `--deny-orphans` in CI and release.
8. Check both source payloads and packed artifacts in module build/verify scripts.
9. Update SPEC, user/developer docs, and paired skills.

Release scripts invoke `iimod`; they do not duplicate extraction rules.

## Acceptance matrix

| Area | Required coverage |
| --- | --- |
| Lexer | QML/JS literals and escapes, multiline calls, comments, false positives in strings, nested arguments, static/interpolated backticks, concatenation rejection |
| Manifest patch | Literal/dynamic calls in `patches[].content`, stable source diagnostics |
| Dynamic catalog | Exact match, missing/stale/duplicate declarations, empty/duplicate keys, unknown field/version, deterministic ordering |
| Placeholders | Reordering, missing/extra/duplicate placeholders, gaps, `%0`, `%100`, `%n`, wrong `.arg()` count |
| Dictionaries | Missing locale/key, malformed JSON, nonstring/empty/marker values, format failures, orphan warning/error modes |
| Repository | Stable module ordering, direct-child discovery, id mismatch, same-value sharing accepted, conflicting values rejected |
| Ownership | Same-value install/uninstall in either order, last-reference removal, pre-migration records, user entry/edit, deterministic conflict behavior |
| Recovery | Sole-owner upgrade, shared divergence, locale removal rollback, reapply repair, rebuilt-registry recovery |
| CLI/package | Help and argument exclusion, directory/package parity, locale override, exact exit codes |
| CI/release | Source and package gates, dirty-tree contract tests, missing-locale/orphan failures, unchanged artifact contract |

## Risks

The main risks are lexer drift as QML/JS syntax evolves, percent text mistaken
for placeholders, ambiguous user-edit classification when old store payloads
are missing, and enabling exact orphan enforcement before the existing catalog
is clean. Fail closed on unrecognized translation calls, keep source-located
diagnostics, and finish baseline migration before activating exact-set release
gates.
