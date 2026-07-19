---
name: ii-module-manage
description: Install, review, upgrade, remove, and repair IIMP modules with iimod on an illogical-impulse (end-4 dots-hyprland) system. Use when the user asks to add/enable/disable/update a shell module, after a dots-hyprland update, or when the shell misbehaves after module changes.
---

# IIMP Module Manager

You operate modules exclusively through the `iimod` CLI. The exit codes are a
stable contract — treat them as law, never as obstacles to route around.

## Hard rules (MUST)

1. **Only iimod touches the shell tree**: never hand-edit anything under
   `~/.config/quickshell/ii/`, never delete `~/.local/share/iimp/` state to
   "fix" things, never edit fenced (`// >>> iimp ... >>>`) regions.
2. **Always gate installs**: run `iimod validate <pkg>` then `iimod check <pkg>`
   before any `iimod install`. A package that fails validation or whose
   capability lint fails MUST NOT be installed — report why instead.
3. **Tier B consent procedure** (module with `patches[]` → install exits 9):
   BEFORE adding `--allow-patches`, you MUST:
   a. read every `patches[]` entry (file, op, anchor, full content),
   b. read the declared `capabilities` and spot-check the code for each
      (`Process`/`execDetached` = runs commands; `XMLHttpRequest` = network),
   c. present the user a plain-language summary: which stock files change,
      what the inserted code does, what the module can do to their system,
   d. wait for the user's explicit consent.
   Never pre-emptively add `--allow-patches` on your own judgment.
4. **Probe failures are final**: exit 4 means the module is incompatible with
   this shell revision. There is no force flag — do not simulate one by
   editing files or the registry. Tell the user to wait for a module update.
5. **After every dots-hyprland update, run `iimod reapply`** — it is idempotent
   and safe anytime. When any iimod command prints the WIPED banner, reapply
   is the ONLY correct next step.
6. **Diagnose before acting**: on odd shell behavior run `iimod doctor` and
   `iimod verify` first, and read the shell log
   (`qs log /run/user/1000/quickshell/by-id/<newest>/log.qslog`).
   `verify` states map to remediations: `module-modified|fence-broken|missing`
   → `iimod repair [<id>]`; `stock-drifted|wiped` → `iimod reapply`;
   `incompatible` → module stays disabled until updated.
7. **Env pitfall on this setup**: fish exports `QT_QPA_PLATFORM=xcb`; any
   manual `qs ipc` call needs `--any-display` (iimod handles this itself).
8. **Never `pkill`/`killall` the shell.** Reloads go through
   `qs -c ii ipc --any-display call iimp reload`.

## Exit codes

| code | meaning | your move |
|---|---|---|
| 0 | ok | report success |
| 3 | validation/lint failed | do not install; show the errors |
| 4 | probes failed | incompatible — no bypass exists |
| 5 | missing dep / conflict | install the dep first, or stop and report |
| 6 | package integrity mismatch | refuse; the package is corrupt or tampered |
| 7 | state error (lock/wiped/corrupt) | lock: one iimod at a time; wiped: reapply; corrupt: `doctor --rebuild-registry` |
| 8 | anchor not found/ambiguous | incompatible with this revision |
| 9 | Tier B needs consent | run the consent procedure (rule 3) |
| 10 | protocol/schema unsupported | upgrade iimod |

## Playbooks

- **Install**: `validate` → `check` → (Tier B? consent) → `install` → confirm
  the widget/window appears → `verify`.
- **Upgrade**: same as install with the new payload/package (registry keeps one
  version; store prunes old ones after post-verify).
- **Remove**: `iimod uninstall <id>`; exit 5 with dependents → show the list,
  ask the user, then `--cascade` if they agree.
- **Post-update recovery**: `iimod reapply` → read its report → explain any
  module marked incompatible (which probe failed and why) to the user.
- **Enable/disable**: `iimod enable|disable <id>` or the Settings → Modules
  page. Dependency closures are automatic and printed.

## 社群中文補充 (zh-TW)

- 「更新 dots 之後一定要跑 `iimod reapply`」——這句話值得直接告訴使用者。
- Tier B 同意流程的中文摘要模板：
  「這個模塊會修改 N 個 stock 檔案：<清單>。插入的程式碼做的事：<白話說明>。
  它宣告的權限：<exec=可執行任意指令 / network=可連網 / …>。
  確認要裝嗎？確認後我會加 `--allow-patches` 重新執行。」
- 模塊出事的求救順序：`iimod doctor` → `iimod verify` → shell log → 回報
  作者（附 verify 狀態與 log 片段），不要自己改檔案。
