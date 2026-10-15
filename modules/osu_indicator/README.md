# osu_indicator - osu! 遊玩狀態指標

Tier A bar 模組，在水平或垂直 bar 顯示 osu!lazer 現在是開著放背景、在選單、正在打圖還是
剛打完一首。它只讀 `osu-state` daemon 寫的狀態檔，模組本身不偵測視窗、不讀 log、不執行
任何外部命令。

> [!IMPORTANT]
> 需要另外安裝並啟用同作者的 `osu-state` daemon（獨立 Rust 專案，尚未公開發佈）
> （`osu-state.service`）。沒有狀態檔時膠囊一律隱藏，不會誤報。

## 功能

| 狀態 | 意思 | 膠囊樣式 |
|---|---|---|
| `off` | osu! 沒在跑 | 隱藏 |
| `idle` | 開著，但不在前景 | 淡色圓環，無中心點 |
| `menu` | 在前景，但沒在打圖 | 淡色圓環加淡色中心點 |
| `playing` | 正在打一首圖（含暫停） | 強調色圓環與中心點、approach circle 收縮動畫、已打時間 |
| `cooldown` | 剛打完，連續打圖的間隔內 | 強調色圓環、中心點呼吸、回到選單的倒數 |

- hover 彈窗顯示狀態、持續時間、冷卻倒數，以及正在打或最後選到的圖（曲名、難度、
  mapper）。
- 強調色可選主題色或 osu! 粉；圓環與文字的顏色變化有過渡動畫。
- 已打時間與倒數每秒更新，用等寬數字避免寬度跳動；垂直 bar 只顯示圖示。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | A，零 stock 修改 |
| 系統 | 選用：`osu-state` daemon 在跑並寫入 `$XDG_RUNTIME_DIR/osu-state.json`；安裝時不檢查 |
| 相容性 | dots-hyprland `446504ad42`、Quickshell `0.2.1` 測試通過 |
| Capabilities | 無 |

狀態檔不存在、daemon 沒跑、或內容不合約定時，膠囊視為 `off` 而隱藏。1.0.1 起
`module.json` 不再把 `osu-state` 列為硬性系統相依，沒有 daemon 的機器也能安裝。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/osu_indicator/
iimod check modules/osu_indicator/
iimod install modules/osu_indicator/
```

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/osu_indicator.json`，也可在
**Settings > Modules > osu! 遊玩指標** 調整。

| Key | 預設 | 說明 |
|---|---|---|
| `showWhenIdle` | `true` | osu! 在背景時也顯示膠囊 |
| `showWhenMenu` | `true` | osu! 在前景選單時也顯示膠囊 |
| `showTimer` | `true` | 圖示旁顯示已打時間或冷卻倒數 |
| `approachAnimation` | `true` | 打圖時的 approach circle 動畫 |
| `accent` | `"theme"` | `"theme"` 跟隨 Material 主題色，`"osu"` 用 osu! 粉 `#ff66aa` |

`showWhenIdle` 與 `showWhenMenu` 都關閉時，只有 `playing` 與 `cooldown` 會出現。

## 資料與行為

- 狀態檔由 daemon 原子寫入（暫存檔再 rename）。模組用 `FileView` 監看檔案，並每 5 秒
  重讀一次作為備援；有倒數或計時在畫面上時另外每秒更新顯示。
- 模組不寫任何檔案；設定檔由 ConfigLoader 模式維護，不碰 shell 的 `config.json`。
- bar 模組每個螢幕各一份實例，各自讀檔；沒有共享狀態，也沒有累計資料。

## 限制

- 狀態的正確性完全取決於 daemon。daemon 死掉而狀態檔殘留時，膠囊會停在最後的狀態；
  `osu-state is-busy` 等指令會檢查 daemon PID，這個模組不會。
- 彈窗的曲名拆分假設 lazer 的 `Artist - Title (mapper) [Diff]` 格式，格式不同時整串
  顯示在曲名欄。
- 垂直 bar 不顯示計時文字。

## 實作說明

| 檔案 | 角色 |
|---|---|
| `bar.qml` | 膠囊：打擊圈圖示、動畫、計時文字、彈窗掛載 |
| `OsuState.qml` | 狀態檔讀取、秒針與備援輪詢 |
| `OsuStateLogic.js` | 純函式：解析狀態檔、顯示規則、時間格式、曲名拆分 |
| `OsuPopup.qml` | hover 彈窗內容 |
| `settings.qml` | 設定頁片段 |
| `ConfigLoader.qml` | 母本 `lib/ConfigLoader.template.qml` 的副本，含 `accent` 值修復 |

## 開發

```bash
node --test modules/osu_indicator/tests/*.test.mjs
iimod validate modules/osu_indicator/
iimod i18n check modules/osu_indicator --locale zh_TW --locale zh_CN --deny-orphans
iimod check modules/osu_indicator/
```
