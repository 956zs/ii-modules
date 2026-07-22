# ii-modules — IIMP（illogical-impulse Module Protocol）

給 end-4/dots-hyprland「illogical-impulse」Quickshell 桌面的**嚴謹社群模塊協議**：
愛好者可以安全地製作、分享、安裝彼此的 shell 模塊（bar 元件、懸浮視窗面板），
帶完整的版本控制、相容性檢測、依賴管理與交易性安裝。

```
┌─ 為什麼需要協議 ──────────────────────────────────────────┐
│ dots-hyprland 更新會 rsync --delete 整個 shell 樹；        │
│ ii 沒有任何版本標記；手工補丁會互相打架、更新即蒸發。      │
│ IIMP 用「特徵探針＋圍欄重組引擎＋母本庫」系統性解決這些。  │
└────────────────────────────────────────────────────────────┘
```

## 快速開始（使用者）

```bash
# 建置工具（或從 Releases 下載 binary 並核對 sha256）
cargo build --release --manifest-path tools/iimod/Cargo.toml
install -Dm755 tools/iimod/target/release/iimod ~/.local/bin/iimod

# 裝一個模塊
iimod validate  modules/network_traffic/   # 驗證 manifest/佈局/權限 lint
iimod check     modules/network_traffic/   # 相容性探針＋依賴＋錨點乾跑
iimod install   modules/network_traffic/   # 交易性安裝（失敗自動回滾）

# 日常
iimod list / info / enable / disable / verify
iimod reapply    # ★ dots-hyprland 更新後必跑：一鍵全部重套
```

設定 app（`Ctrl+Super+,`）會多出 **Modules** 頁：開關模塊、看各模塊設定。

## 快速開始（模塊作者）

```bash
iimod init my_widget          # 腳手架
# …寫 QML（bar.qml 根必須是視覺 Item；main.qml 根必須是 Scope/PanelWindow）
iimod suggest my_widget/      # 自動推導 probes 與 capabilities 建議
iimod validate my_widget/ && iimod check my_widget/ && iimod install my_widget/
iimod pack my_widget/         # 產出 my_widget-0.1.0.iimod 分享給朋友
```

參考實作：[`modules/network_traffic/`](modules/network_traffic/)（含逐檔說明）、
最小視窗範例 [`examples/hello_window/`](examples/hello_window/)。

## 核心概念

| 概念 | 一句話 |
|---|---|
| **Tier A 插槽模塊** | 純資料夾，載入到 bar / window 插槽，零 stock 修改，壞掉只有該格空白 |
| **Tier B 補丁模塊** | 以結構化 insert-only 補丁修改 stock 檔；安裝需 `--allow-patches` 明確同意 |
| **探針（probe）** | ii 沒有版本號——相容性用「檔案存在／包含字面字串」直接驗證 API 表面 |
| **圍欄重組引擎** | 所有補丁包在 `// >>> iimp id/n >>>` 圍欄內；每次變更從乾淨基底重算全部，安裝順序不影響結果 |
| **母本庫（store）** | 完整狀態存在 `~/.local/share/iimp/`（rsync 清除區之外）；`reapply` 隨時可整批重建 |
| **capabilities** | 模塊必須誠實宣告 exec/network/filesystem-write/dbus；靜態 lint 交叉查核，不符拒裝 |

完整規格：[`spec/SPEC-1.0.md`](spec/SPEC-1.0.md)（含威脅模型——capabilities 是知情同意，不是沙箱；裝前請審查程式碼）。

## AI Agent Skills

`.claude/skills/` 內含兩個 Claude Code project skills，讓這個專案裡的 agent 受協議約束：

- **ii-module-author** — 開發紀律：命名規則、自包含、探針宣告、semver、發佈清單
- **ii-module-manage** — 安裝紀律：必跑 validate+check、Tier B 同意流程、exit code 對照、更新後 reapply

若要帶到別的模塊專案，複製到該專案的 `.claude/skills/`，不要裝進全域 `~/.claude/skills/`。

## Release workflow（多人協作）

正式 release 只從 git tag 產生。maintainer 合併版本 bump PR 後，建立並推送 tag：

```bash
git tag v1.0.2
git push origin v1.0.2
```

GitHub Actions 會自動跑 `tools/release/build.sh` 和 `tools/release/verify.sh`，
產出 Linux binary、`.iimod`、starter zip、`SHA256SUMS`，再發布 GitHub Release。

本機 dry-run：

```bash
tools/release/build.sh --allow-dirty v1.0.2
tools/release/verify.sh dist/release/v1.0.2
```

`build.sh` 預設要求 git tree 乾淨；`--allow-dirty` 只給本機試包用，正式 CI 不使用。

## Exit codes（穩定契約）

`0` ok · `3` 驗證失敗 · `4` 探針失敗（絕對擋）· `5` 依賴/衝突 · `6` 完整性
· `7` 狀態錯誤 · `8` 錨點失敗 · `9` Tier B 需 `--allow-patches` · `10` 協議版本

## Repo 佈局

```
spec/            SPEC-1.0.md＋fixtures（規範與測試語料）
tools/iimod/     Rust CLI（50 tests：單元＋對迷你 stock 樹的整合矩陣）
tools/release/   release build/verify 腳本
.github/         tag-triggered release workflow
.claude/skills/  Claude Code project skills ×2
skills/          portable skill copies ×2
modules/         參考模塊（network_traffic）
examples/        最小範例（hello-window）
```

License: MIT（工具/規格/host QML；各模塊依其 manifest 自訂）。
