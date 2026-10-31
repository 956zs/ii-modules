# aula_keys - AULA WIN 60 HE 音遊按鍵疊加層

Tier A window 模組，在螢幕角落用不攔截點擊的浮層顯示 AULA WIN 60 HE 上設定的按鍵：
鍵帽、即時鍵程、觸發點、每鍵次數、總數、KPS 與最高 KPS。資料全部來自
`aulactl feed` 的 NDJSON 輸出；模組不直接碰鍵盤，也只在浮層顯示時執行 feed。

> [!IMPORTANT]
> `aulactl feed` 執行期間會佔住鍵盤的 travel-test stream，其他 `aulactl` 與
> `aula-gui` 指令會回報 busy。預設模式只在打 osu! 圖時顯示並執行 feed；
> 改成「一律顯示」會讓 feed 一直執行。

## 功能

- 每個設定的按鍵一顆鍵帽：鍵帽由上往下填滿代表目前鍵程（`mm / max_mm`），橫線是
  觸發點，按下時邊框與填色換成主題強調色。
- 鍵帽下方是該鍵的按下次數；底部一行顯示目前 KPS（1 秒滑動視窗）、最高 KPS 與總數。
- feed 的 `waiting`、`lost`、`error` 與重啟狀態以一行淡色小字顯示，狀態改變時才
  寫一行 log。
- 位置可選六個角落或上下置中，大小、透明度、離邊距離、顯示的螢幕都可調。
- 顏色與字型跟隨 ii 主題（`Appearance`）。

| 顯示模式（`mode`） | 何時顯示並執行 feed |
|---|---|
| `playing`（預設） | `osu-state` 回報 `playing` |
| `focused` | `menu`、`playing` 或 `cooldown`（osu! 在前景，或剛打完一首） |
| `always` | 一律 |
| `off` | 永不 |

離開想要的狀態後浮層會再停留 `hideDelaySecs` 秒，重打一首（退出再開始）不會閃爍，
也不會重啟 feed。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | A，零 stock 修改 |
| 系統 | `aulactl`（含 `feed` 子指令）在 shell 的 `PATH` 或設定的路徑；`playing`、`focused` 模式需要 `osu-state` daemon |
| 相容性 | dots-hyprland `446504ad42`、Quickshell `0.3.2` 測試通過 |
| Capabilities | `exec`：執行 `aulactl feed` |

沒有 `osu-state` 狀態檔時 osu! 視為 `off`，`playing` 與 `focused` 模式不會顯示。
`aulactl` 不存在或立刻結束時，模組以 1、2、4 … 最多 30 秒的間隔重試，浮層顯示
「Feed stopped, retrying」。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/aula_keys/
iimod check modules/aula_keys/
iimod install modules/aula_keys/
```

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/aula_keys.json`，也可在
**Settings > Modules > AULA 按鍵疊加層** 調整。

| Key | 預設 | 說明 |
|---|---|---|
| `mode` | `"playing"` | `playing`、`focused`、`always`、`off`，見上表 |
| `keys` | `"KeyZ,KeyX"` | 按鍵代碼（`KeyZ`、`Digit1`、`Space`、`Semicolon` …），逗號或空白分隔，最多 16 個，無效時回到 `KeyZ,KeyX` |
| `corner` | `"bottomRight"` | `topLeft`、`topCenter`、`topRight`、`bottomLeft`、`bottomCenter`、`bottomRight` |
| `marginPx` | `24` | 離螢幕邊緣的距離（0–400） |
| `scalePercent` | `100` | 大小百分比（50–300） |
| `opacityPercent` | `90` | 不透明度百分比（20–100） |
| `monitor` | `""` | 顯示的輸出名稱（例如 `eDP-1`），空字串用第一個螢幕 |
| `showCounts` | `true` | 鍵帽下方的次數 |
| `showStats` | `true` | KPS、最高與總數那一行 |
| `resetOnSession` | `true` | 每個新 session 歸零計數 |
| `resetRequest` | `0` | 設定頁「Reset counters now」按鈕遞增它；數值本身無意義 |
| `hideDelaySecs` | `3` | 離開想要的狀態後再停留的秒數（0–60） |
| `depthHz` | `60` | 傳給 feed 的 `--depth-hz`；`0` 用 feed 預設 |
| `binary` | `"aulactl"` | `aulactl` 指令名稱或絕對路徑 |

設定頁有 osu! standard（`KeyZ,KeyX`）、mania 4K（`KeyD,KeyF,KeyJ,KeyK`）與
mania 7K（`KeyS,KeyD,KeyF,Space,KeyJ,KeyK,KeyL`）三個快捷按鈕。

## 資料與行為

- feed 的命令列是 `<binary> feed --keys <keys> [--depth-hz <n>]`，參數逐一傳遞，
  不經過 shell。浮層隱藏時送 SIGTERM；按鍵、`depthHz` 或 `binary` 改變時立即重啟。
- feed 非預期結束時以指數退避重啟；收到 `hello`（鍵盤已連線）後退避歸零。
- 次數只算 `press` 事件。KPS 用 feed 的 `t`（毫秒）計算 1 秒滑動視窗，事件之間用
  牆上時鐘推進，所以停手後 KPS 會自然歸零；feed 重啟時視窗清空，次數保留。
- 最高 KPS 在每次按下時取樣；視窗內的數量只會在按下時增加，所以這就是精確最大值。
- session 是「浮層出現」或「osu! 開始一首新圖」（`playing` 且 `since` 改變）。
  `resetOnSession` 關閉時只有手動重置才歸零。
- 計數只在記憶體中，不寫檔；shell 重新載入後歸零。
- IPC：`qs -c ii ipc --any-display call aula_keys reset` 歸零，
  `... call aula_keys status` 回傳模式、osu! 狀態、是否顯示、feed 狀態與計數的 JSON。

## 限制

- `press`/`release` 是 `aulactl` 依鍵程推算的近似值（見 aulactl `docs/feed.md`），
  適合計數與 KPS，不適合判定時間。
- `focused` 模式在 `cooldown` 期間無法分辨 osu! 是否在前景，一律顯示。
- 鍵程條的觸發點只取 `hello` 的 `point`；rapid trigger 的 press/release 距離不畫出來。
- 浮層只出現在一個螢幕上。

## 實作說明

| 檔案 | 角色 |
|---|---|
| `main.qml` | window slot：ConfigLoader owner、顯示狀態機、session 重置、IPC |
| `KeyFeed.qml` | `aulactl feed` 行程、NDJSON 解析、每鍵 model、計數與退避重啟 |
| `KeyOverlay.qml` | layer-shell 浮層（Overlay 層、空 mask 讓點擊穿透） |
| `OsuWatch.qml` | 精簡自 `osu_indicator/OsuState.qml` 的狀態檔讀取 |
| `OsuStateLogic.js` | `osu_indicator` 的 vendored 副本，只有檔頭不同 |
| `AulaKeysLogic.js` | 純函式：按鍵清單、行解析、KPS 視窗、顯示狀態機、退避 |
| `settings.qml` | 設定頁片段 |
| `ConfigLoader.qml` | 母本 `lib/ConfigLoader.template.qml` 的副本，含選項修復 |
| `tests/feeder.sh` | 開發用假 feed，輸出合約格式的行 |

## 開發

```bash
node --test modules/aula_keys/tests/*.test.mjs
iimod validate modules/aula_keys/
iimod i18n check modules/aula_keys --locale zh_TW --locale zh_CN --deny-orphans
iimod check modules/aula_keys/
```

不接鍵盤測試時，把 `binary` 設成假 feed 的絕對路徑、`mode` 設成 `always`：

```bash
tests/feeder.sh feed --keys KeyZ,KeyX   # 在模組目錄下執行可直接看輸出
```
