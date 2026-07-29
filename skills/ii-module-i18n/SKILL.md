---
name: ii-module-i18n
description: Complete isolated IIMP module translation work after feature strings freeze. Reads target docs and source, but writes only target translations/*.json and i18n.sources.json; runs target-scoped iimod i18n extract/check and returns ambiguities to the feature owner.
---

# IIMP Module i18n

Translate one frozen IIMP module without changing feature behavior. The runtime
contract is `Translation.tr("English source")` plus payload dictionaries; missing
entries display the English source. `i18n.sources.json` is development metadata,
not a `module.json` field or a second runtime.

## Required Input

Receive a target payload path from the feature owner. Source strings must be
frozen before work begins. If the target or freeze state is unclear, stop and
return that ambiguity to the feature owner.

## Ownership Boundary

Read the repository `AGENTS.md`, `README.md`, `spec/SPEC-1.0.md`, and the target
module's README, `module.json`, QML, JS, existing translations, and existing
`i18n.sources.json` before editing.

Write only these paths inside the target payload:

- `translations/*.json`
- `i18n.sources.json`

Never modify QML, JS, `module.json`, version fields, README files, tests,
capabilities, settings schemas, other modules, generated catalogs, CI/release
files, or live shell/state files to silence a check. Never install, reapply,
enable, disable, uninstall, repair, or otherwise mutate live IIMP state.

## Procedure

1. Run target-scoped extraction before editing:

   ```bash
   iimod i18n extract <target>
   ```

2. Compare the extracted set with every target `translations/*.json`. Portable
   work requires a complete, canonical `zh_TW`; first-party work in this
   repository requires exact `zh_TW` and `zh_CN` catalogs with no orphans.
3. For each nonliteral diagnostic, prove the finite source set from the frozen
   target source and documentation. Add or correct an exact declaration only
   when its source unit, whitespace-normalized expression, and complete source
   set are unambiguous. Otherwise stop and report the source location and
   ambiguity to the feature owner.
4. Translate source meaning in context. Preserve exact English keys and the full
   placeholder multiset. Do not use source rewrites, empty values, or placeholder
   markers such as `TODO`, `TBD`, `FIXME`, `TRANSLATE`, or `UNTRANSLATED`.
5. Canonicalize dictionaries by Unicode-codepoint key order, two-space JSON, and
   exactly one final newline. Keep `i18n.sources.json` strict: `schemaVersion: 1`,
   declarations ordered by source then expression, and each source list ordered
   by Unicode codepoint.
6. Re-run extraction and the target policy check after every correction:

   ```bash
   iimod i18n extract <target>
   iimod i18n check <target> \
     --locale zh_TW --locale zh_CN --deny-orphans
   ```

   Outside this repository, use the requested locales; when none are specified,
   run `iimod i18n check <target>` so the portable `zh_TW` default applies.

## Strict Rules

- `Translation.tr` sources are exact, nonempty English strings with no leading
  or trailing whitespace or control characters.
- Only canonical numeric placeholders `%1` through `%99` are supported. Indices
  are contiguous from `%1` to `%N`; each call site has exactly `N` immediate
  `.arg()` calls. `%n` is forbidden because the runtime has no plural API.
- A translation preserves the source placeholder multiset exactly; placeholder
  order may change.
- Interpolation, concatenation, identifiers, and member expressions are not
  literal sources. Each controlled dynamic call needs exactly one matching
  declaration. Duplicate, stale, unmatched, incomplete, or guessed declarations
  are forbidden.
- Orphans are not deleted until extraction proves they are unused, including
  QML/JS and `module.json` patch content. Under exact checking, proven orphans
  must be removed rather than retained to make the catalog larger.
- Same locale/source values may be shared across modules. Different values are a
  repository conflict; do not choose one silently or edit another module.
- Identical source/translation warnings are allowed only when the target term is
  intentionally unchanged; report each intentional case.

## Completion Report

Report the target, files changed, locales completed, both target-scoped commands
and exit status, intentional identical-value warnings, and any unresolved source
wording or dynamic-provenance ambiguity. Do not claim completion unless extract
and the applicable exact check both exit 0.
