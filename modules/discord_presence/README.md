# discord_presence - Discord 動態狀態膠囊

Tier A bar 模組，在水平或垂直 bar 顯示 `discord-rpc-proxy`（Discord Rich Presence
daemon）現在偵測到哪個遊戲、有沒有顯示在 Discord，以及暫停、離開、未連線等狀態。
模組只透過 `discord-rpc-proxy watch` 跟隨 daemon，本身不偵測遊戲、不連 Discord。

> [!IMPORTANT]
> 需要另外安裝並執行同作者的 `discord-rpc-proxy` daemon（獨立 Rust 專案），而且
> 版本要支援 `watch`、`toggle` 與 `status --json` 子指令。daemon 沒在跑時膠囊顯示
> 「daemon 未執行」狀態，每 10 秒重試一次。

## 功能

| 狀態 | 意思 | 膠囊樣式 |
|---|---|---|
| `down` | daemon 沒在跑，或找不到執行檔 | 半透明手把圖示，無文字 |
| `idle` | daemon 在跑，沒偵測到遊戲 | 淡色手把圖示 |
| `playing` | 偵測到遊戲 | 手把圖示加遊戲名稱；已顯示在 Discord 時圖示為強調色 |
| `paused` | 暫停顯示 Discord 動態 | `visibility_off` 圖示，遊戲名稱變淡並加刪除線 |

- 圖示右下角的小圓點：錯誤色表示 Discord 未連線，tertiary 色表示使用者離開中
  （idle）；未連線優先。
- 左鍵切換暫停（執行 `discord-rpc-proxy toggle`），新狀態由 watch 串流帶回；
  daemon 沒在跑時左鍵改為立刻重試連線。
- hover 彈窗顯示遊戲名稱、是否顯示在 Discord、遊戲已執行時間、累計遊玩時數，
  以及離開與 Discord 連線狀態。
- 遊戲名稱最寬 160 px，超出時以省略號截斷；垂直 bar 只顯示圖示。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | A，零 stock 修改 |
| 系統 | 選用：`discord-rpc-proxy` 在 `PATH` 中（或在設定填路徑）且 daemon 在跑；安裝時不檢查 |
| 相容性 | 尚未在 live shell 測試，`module.json` 未填 `testedOn` |
| Capabilities | `exec`：執行 `discord-rpc-proxy watch` 與 `discord-rpc-proxy toggle` |

找不到執行檔、daemon 沒在跑、或 watch 結束時，膠囊回到 `down` 並重試：曾經收到過
狀態的串流結束（多半是 daemon 重啟）1 秒後重試，其他情況每 10 秒重試。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/discord_presence/
iimod check modules/discord_presence/
iimod install modules/discord_presence/
```

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/discord_presence.json`，也可在
**Settings > Modules > Discord 動態** 調整。

| Key | 預設 | 說明 |
|---|---|---|
| `hideWhenIdle` | `false` | 沒偵測到遊戲且未暫停時隱藏膠囊；`down` 狀態也一併隱藏 |
| `binary` | `"discord-rpc-proxy"` | 執行檔名稱（從 `PATH` 尋找）或路徑；開頭的 `~/` 會展開，空值回到預設 |

修改 `binary` 會立刻以新指令重新啟動 watch。

## 資料與行為

- watch 每次狀態改變輸出一行 JSON；模組忽略無法解析或不符格式的行，保留上一個
  有效狀態。
- `playtime_secs` 只在狀態改變時更新。彈窗開著時，模組以收到該行的時間往後推算：
  偵測到遊戲且未離開時每秒加一，離開時停住，與 daemon 的計時規則相同。daemon
  關閉遊玩時數統計（送 `null`）時不顯示累計列。
- 只有彈窗開著且偵測到遊戲時才有每秒更新的計時器。
- 模組不寫任何檔案；設定檔由 ConfigLoader 模式維護，不碰 shell 的 `config.json`。
  暫停狀態由 daemon 保存，重開後仍保留。

## 限制

- bar 模組每個螢幕各一份實例，各自執行一個 `watch` 程序。
- 啟用 bar 的 click-to-show tooltips 時，左鍵同時切換暫停並顯示彈窗。
- 推算的累計時數可能與 daemon 實際值差幾秒；下一行狀態到達時會校正。
- `discord-rpc-proxy` 的 stderr 只在第一次連線失敗時寫進 shell log，不顯示在 UI。

## 實作說明

| 檔案 | 角色 |
|---|---|
| `bar.qml` | 膠囊：圖示、狀態小圓點、遊戲名稱、左鍵切換、彈窗掛載 |
| `PresenceWatch.qml` | 執行並重試 `watch`、執行 `toggle`、秒針 |
| `PresenceLogic.js` | 純函式：解析狀態行、狀態分類、顯示規則、時數推算、時間格式、執行檔路徑 |
| `PresencePopup.qml` | hover 彈窗內容 |
| `settings.qml` | 設定頁片段 |
| `ConfigLoader.qml` | 母本 `lib/ConfigLoader.template.qml` 的副本，含 `binary` 空值修復 |

## 開發

```bash
node --test modules/discord_presence/tests/*.test.mjs
iimod validate modules/discord_presence/
iimod i18n check modules/discord_presence --locale zh_TW --locale zh_CN --deny-orphans
iimod check modules/discord_presence/
```
