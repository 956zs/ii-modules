<div align="center">

# ii-modules — IIMP（illogical-impulse Module Protocol）

給 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)「illogical-impulse」Quickshell 桌面的**嚴謹社群模塊協議**：
愛好者可以安全地製作、分享、安裝彼此的 shell 模塊（bar 元件、懸浮視窗面板），
帶完整的版本控制、相容性檢測、依賴管理與交易性安裝。

[![CI](https://github.com/956zs/ii-modules/actions/workflows/ci.yml/badge.svg)](https://github.com/956zs/ii-modules/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/956zs/ii-modules)](https://github.com/956zs/ii-modules/releases)
[![License: MIT](https://img.shields.io/github/license/956zs/ii-modules)](LICENSE)

</div>

> [!IMPORTANT]
> **為什麼需要協議**
>
> dots-hyprland 更新會 `rsync --delete` 整個 shell 樹；ii 沒有任何版本標記；手工補丁會互相打架、更新即蒸發。
> IIMP 用「特徵探針＋圍欄重組引擎＋母本庫」系統性解決這些。

## 目錄

- [快速開始（使用者）](#快速開始使用者)
- [快速開始（模塊作者）](#快速開始模塊作者)
- [模塊國際化](#模塊國際化)
- [核心概念](#核心概念)
- [AI Agent Skills](#ai-agent-skills)
- [Release workflow（多人協作）](#release-workflow多人協作)
- [模塊更新（iimod update）](#模塊更新iimod-update)
- [Exit codes（穩定契約）](#exit-codes穩定契約)
- [Repo 佈局](#repo-佈局)

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

# 更新（聯邦式：每個模塊記住自己的來源，URL 安裝自動記錄）
iimod install https://example.com/mods/my_widget-1.0.0.iimod   # origin 自動＝同目錄 index.json
iimod update --dry-run   # 查有什麼新版
iimod update             # 全部更新（Tier B 更新需再次 --allow-patches）
```

設定 app（`Ctrl+Super+,`）會多出 **Modules** 頁：開關模塊、看各模塊設定。

`iimod` 1.2.0+ 第一次執行 mutating command 時會在
`~/.local/share/iimp/lock` 安裝永久 legacy fence，並改由
`mutation.lock.v2` 協調新版交易。這會讓 1.1.x 等舊 binary 在任何 host
寫入前失敗；若舊 CLI 顯示 `another iimod is running (pid 1)`，請升級 CLI，
**不要刪除 lock**。權威 host generation 與不可變 bundle 位於
`~/.local/share/iimp/host/`，`verify` 會檢查 bundle、live assets、sentinel、
imports 與 host fences，避免舊 UI 被覆寫後仍誤報 intact。

## 快速開始（模塊作者）

```bash
iimod init my_widget          # 腳手架
# …寫 QML（bar.qml 根必須是視覺 Item；main.qml 根必須是 Scope/PanelWindow）
iimod suggest my_widget/      # 自動推導 probes 與 capabilities 建議
iimod i18n extract my_widget/ # 列出 Translation.tr 英文來源
iimod i18n check my_widget/   # 可攜式最低要求：完整 zh_TW catalog
iimod validate my_widget/ && iimod check my_widget/ && iimod install my_widget/
iimod pack my_widget/         # 產出 my_widget-0.1.0.iimod 分享給朋友
```

參考實作：[`modules/network_traffic/`](modules/network_traffic/)（含逐檔說明）、
最小視窗範例 [`examples/hello_window/`](examples/hello_window/)。

## 模塊國際化

IIMP v1 不引入第二套翻譯 runtime。QML/JS 直接使用
`Translation.tr("English source")`，模塊以
`translations/<locale>.json` 提供平坦的英文來源到譯文字典；找不到目前語系或
key 時，shell 顯示傳入的英文來源。這些字典由 `iimod` 安裝流程合併到 shell
產生的語系字典，既有同值貢獻者會共同保留 reference，不同值維持可預測的
first-value-wins runtime 行為。

`iimod i18n` 是開發期工具，不改變 `protocolVersion: 1` 或 `module.json`
schema：

```bash
# 單一 payload 或 .iimod；extract 為唯讀
iimod i18n extract modules/my_widget
iimod i18n check modules/my_widget                 # 預設要求 zh_TW
iimod i18n check modules/my_widget --locale zh_CN  # 重複 flag 可指定其他集合

# 本 repository 的一等模塊政策：zh_TW + zh_CN，且 catalog 必須完全精確
iimod i18n extract --all
iimod i18n check --all --deny-orphans
```

`extract` 以確定性順序掃描 payload 的 `.qml`、`.js` 與
`module.json` 的 `patches[].content`。若 `Translation.tr(...)` 不是單一字面量，
必須在 payload 根的 `i18n.sources.json` 宣告可證明的有限來源集合；此檔僅是
開發 metadata，不參與 runtime lookup，也不是 manifest 欄位。未宣告的動態
呼叫、插值／串接、重複或失效宣告、無法證明的來源都會失敗。

可攜式模塊至少提供完整且格式正規的 `zh_TW`；本 repository 的一等模塊同時
要求 `zh_TW` 與 `zh_CN`，並禁止兩個 catalog 出現 orphan。英文 key 與譯文
不可為空或含控制字元，catalog 必須依 Unicode codepoint 排序、使用兩空格
JSON 並只有一個結尾換行。`%1` 到 `%99`
必須連續，譯文保留相同 placeholder multiset，呼叫端緊接的 `.arg()` 數量必須
一致；目前 runtime 沒有 plural API，因此禁止 `%n`。一般 check 對 orphan
提出警告，`--deny-orphans` 使其失敗；repository check 允許同 locale/key 的
同值共享，但不同譯文是衝突錯誤。

功能 owner 先凍結英文來源與動態來源 provenance，再把翻譯交給獨立 i18n
subagent。該 subagent 只可修改目標模塊的 `translations/*.json` 與
`i18n.sources.json`；不得改 QML/JS、manifest、版本、README 或測試來消除
檢查錯誤，任何語意或來源歧義都必須退回功能 owner。

## 核心概念

| 概念 | 一句話 |
|---|---|
| **Tier A 插槽模塊** | 純資料夾，載入到 bar / window 插槽，零 stock 修改，壞掉只有該格空白 |
| **Tier B 補丁模塊** | 以結構化 insert-only 補丁修改 stock 檔；安裝需 `--allow-patches` 明確同意 |
| **探針（probe）** | ii 沒有版本號——相容性用「檔案存在／包含字面字串」直接驗證 API 表面 |
| **圍欄重組引擎** | 所有補丁包在 `// >>> iimp id/n >>>` 圍欄內；每次變更從乾淨基底重算全部，安裝順序不影響結果 |
| **母本庫（store）** | 完整模塊狀態存在 `~/.local/share/iimp/`（rsync 清除區之外）；`reapply` 隨時可整批重建 |
| **Host generation** | `iimod` 1.2.0+ 以不可變 generation bundle 保存 host QML/圍欄；舊 binary 在寫入前被永久 legacy lock fence 阻擋，較舊的新協定 binary 也不得降級 host |
| **capabilities** | 模塊必須誠實宣告 exec/network/filesystem-write/dbus；靜態 lint 交叉查核，不符拒裝 |

完整規格：[`spec/SPEC-1.0.md`](spec/SPEC-1.0.md)。

> [!WARNING]
> capabilities 是知情同意，不是沙箱；裝前請審查程式碼。

## AI Agent Skills

`.claude/skills/` 內含三個 Claude Code project skills，讓這個專案裡的
agent 受協議約束：

- **ii-module-author** — 開發紀律：命名規則、自包含、探針宣告、semver、發佈清單
- **ii-module-i18n** — 翻譯隔離：只寫 catalog／動態來源 metadata，執行
  target extract/check，歧義退回功能 owner
- **ii-module-manage** — 安裝紀律：必跑 validate+check、Tier B 同意流程、exit code 對照、更新後 reapply

> [!TIP]
> 若要帶到別的模塊專案，複製到該專案的 `.claude/skills/`，不要裝進全域 `~/.claude/skills/`。

## Release workflow（獨立產品版本）

CLI 與每個模塊都是獨立產品，不共用版本號或 GitHub Release。日常發布只需使用單一入口；它會從 manifest/Cargo 自動推導版本與 tag，先完整建置、驗證，再於明確指定 `--push` 時建立 annotated tag 並推送以觸發 GitHub Actions：

```bash
# 本機完整 dry-run，不建 tag
tools/release/publish.sh module animation_tuner
tools/release/publish.sh cli

# 已合併至乾淨且同步的 main 後正式發布
tools/release/publish.sh module animation_tuner --push
tools/release/publish.sh cli --push
```

`--push` 要求工作樹乾淨、目前分支為 `main`，且 `HEAD` 精確等於 `origin/main`；本地或遠端已有同名 tag 也會拒絕。只需在 dirty 開發樹試跑時使用 `--allow-dirty`，它不能與 `--push` 並用。

| 產品 | Tag | Release 內容 |
|---|---|---|
| 模塊 | `module/<id>/v<semver>` | `<id>-<semver>.iimod`、`SHA256SUMS` |
| iimod CLI | `iimod/v<semver>` | `iimod-linux-x86_64`、`SHA256SUMS` |

每個 namespaced tag 只建置並發布對應產品，Release 一律不取代 repository-wide Latest。正式 Release 由 `publish.sh --push` 處理。底層機制是建立一個已存在且指向目前 commit 的 namespaced tag；以下手動 tag 指令只供維護／故障排查，不是日常發布流程：

```bash
git tag module/network_traffic/v1.5.0
git push origin module/network_traffic/v1.5.0

# CLI 有自己的版本生命週期
git tag iimod/v0.2.0
git push origin iimod/v0.2.0
```

Pages 會在 Release 變更後掃描所有 namespaced Releases，驗證精確資產名稱並重算 SHA256，再輸出：

- `https://ii.n1cat.xyz/index.json`：所有模塊各自最高 semver 的 `indexVersion: 1` 聚合索引
- `https://ii.n1cat.xyz/downloads/iimod/linux-x86_64`：最高 CLI semver 的穩定下載
- `https://ii.n1cat.xyz/downloads/iimod/linux-x86_64.sha256`：對應 checksum

因此合併模塊版本 bump 只會更新原始碼 catalog；對應的 `module/<id>/v<version>` Release 成功後，網站才會啟用下載。

首次啟用此流程時，建議先以 `tools/release/publish.sh cli --push` 發布目前 Cargo 版本的 CLI，再以 `tools/release/publish.sh module <id> --push` 發布模塊。Pages projection 會按目前存在的穩定 Releases 完整重建輸出：尚無 CLI 時不提供穩定 binary，尚無模塊時則輸出合法的空索引；刪除 Release 也會在下一次部署移除對應產品。

### Legacy `v1.4.0` 更新來源遷移

既有 `network_traffic 1.4.0` 安裝記住的是 `v1.4.0/index.json`。新 `module/network_traffic/v1.5.0` 發布且 Pages index 更新後，產生一次性 bridge：

```bash
curl --fail --location --output /tmp/iimp-index.json https://ii.n1cat.xyz/index.json
npm --prefix site run legacy:index -- \
  --index /tmp/iimp-index.json \
  --module network_traffic \
  --output /tmp/network-traffic-legacy-index.json
```

核對輸出的 version、GitHub HTTPS 資產 URL 與 SHA256 後，將它**取代**舊 `v1.4.0` Release 的 `index.json` 資產。不要向 legacy Release 加入新產品 artifact；它只作為舊 origin 到新不可變模塊資產的相容橋。

<details>
<summary>本機 dry-run（開發用）</summary>

```bash
# 模塊
tools/release/build-module.sh --allow-dirty modules/network_traffic module/network_traffic/v1.5.0
tools/release/verify-module.sh dist/release/module/network_traffic/v1.5.0

# CLI
tools/release/build-cli.sh --allow-dirty iimod/v1.1.0
tools/release/verify-cli.sh dist/release/iimod/v1.1.0
```

建置腳本預設要求 git tree 乾淨；`--allow-dirty` 只給本機試包用，正式 CI 不使用。

</details>

## 模塊更新（`iimod update`）

去中心化設計——沒有中央倉庫，每個模塊在安裝時記住自己的來源
（存在 registry v2，協議零改動）。**本 repository 發佈的 `.iimod` 內嵌穩定的 Pages origin**
（`https://ii.n1cat.xyz/index.json`）；Pages 會從各自獨立的 namespaced Releases 投影最高 semver。拿到檔案就能裝、
裝了就能 `iimod update`。其他發佈者仍可在 pack 時內嵌自己的 index；沒內嵌時，從 URL 安裝自動記同目錄的 `index.json`；
`--origin` 永遠可顯式覆寫（優先序：flag ＞ 內嵌 ＞ URL 同目錄）。來源是一個靜態 `index.json`，掛在任何
HTTPS 位置（GitHub raw / Releases / 自架皆可）：

<details>
<summary>index.json 範例</summary>

```json
{"indexVersion": 1,
 "modules": {
   "network_traffic": {
     "version": "1.5.0",
     "url": "network_traffic-1.5.0.iimod",
     "sha256": "…"}}}
```

</details>

- `url` 可相對於 index 位置；傳輸用系統 `curl`（僅 `https://` 與 `file://`，
  後者供區網分享與離線測試）
- 下載一律驗 `sha256`，不符即 exit 6，不落地
- Tier B 模塊的更新必須重新 `--allow-patches`（新版補丁可能不同）
- 更新走既有的交易性 install 管線：失敗回滾、設定保留、origin 延續
- `iimod pack` 強制要求 `--origin`（或明確 `--no-origin` 退出，僅供本機/開發用途）——
  沒帶任一 flag 會直接拒絕打包

## Exit codes（穩定契約）

| Exit code | 意義 |
|---|---|
| `0` | ok |
| `3` | 驗證失敗 |
| `4` | 探針失敗（絕對擋） |
| `5` | 依賴/衝突 |
| `6` | 完整性 |
| `7` | 狀態錯誤 |
| `8` | 錨點失敗 |
| `9` | Tier B 需 `--allow-patches` |
| `10` | 協議版本 |

## Repo 佈局

```text
spec/            SPEC-1.0.md＋fixtures（規範與測試語料）
tools/iimod/     Rust CLI（含單元與整合測試，涵蓋翻譯、交易、host generation 與 lock 回歸）
tools/release/   獨立 module / iimod CLI release build、verify 腳本
.github/         namespaced tag release workflows 與 Pages release projection
.claude/skills/  Claude Code project skills ×3
skills/          portable skill copies ×3
modules/         參考模塊（network_traffic）
examples/        最小範例（hello_window）
```

---

License: MIT（工具/規格/host QML；各模塊依其 manifest 自訂）。
