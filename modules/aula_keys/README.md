# aula_keys - AULA WIN 60 HE 音遊按鍵疊加層

Tier A window + bar 模組，在螢幕角落用不攔截點擊的疊加層顯示 AULA WIN 60 HE 上設定的
按鍵：鍵帽、即時鍵程、觸發點、每鍵次數、總數、KPS 與最高 KPS；bar 上的鍵盤圖示顯示
疊加層狀態，點開是快速設定。資料全部來自 `aulactl feed` 的 NDJSON 輸出；模組不直接碰
鍵盤，也只在疊加層顯示時執行 feed。

> [!IMPORTANT]
> `aulactl feed` 執行期間會佔住鍵盤的 travel-test stream，其他 `aulactl` 與
> `aula-gui` 指令會回報 busy。預設模式只在打 osu! 圖時顯示並執行 feed；
> 改成「一律顯示」會讓 feed 一直執行。

## 功能

- 每個設定的按鍵一顆鍵帽，鍵程（`mm / max_mm`）有兩種畫法：預設是由下往上的填色，
  裁成鍵帽的圓角形狀、用主題強調色的柔和漸層；或是鍵帽右緣的細長條。也可以關掉。
- 觸發點是鍵帽側邊的短刻痕（長條模式畫在長條旁），低對比、不穿過字。鍵程以約 40 ms
  的動畫平滑；按下狀態（強調色邊框、鍵帽變亮）則立即切換。字的顏色依背後是鍵帽還是
  填色自動挑對比較高的主題色。
- 鍵帽下方是該鍵的按下次數；底部一行顯示目前 KPS（1 秒滑動視窗）、最高 KPS 與總數。
- feed 的 `waiting`、`lost`、`error` 與重啟狀態以一行淡色小字顯示，狀態改變時才
  寫一行 log。
- 位置可選六個角落或上下置中，大小、透明度、離邊距離、顯示的螢幕都可調。
- 顏色與字型跟隨 ii 主題（`Appearance`）。

### Bar 圖示與快速設定

| 圖示顏色 | 意思 |
|---|---|
| 淡色 | 模式 `off`、疊加層隱藏（等 osu!），或疊加層部分沒載入 |
| 強調色（實心） | feed 已連上鍵盤，資料進來中 |
| 半強調色 | feed 啟動中 |
| 偏紅 | 鍵盤 waiting、busy、lost，或 feed 出錯、重試中 |

- hover 顯示模式、feed 狀態與鍵盤型號。
- 點一下打開快速設定面板：顯示模式、按鍵預設（osu! standard、mania 4K、mania 7K；
  不符合任何預設時標成「Custom」並列出目前按鍵）、鍵程畫法、三個開關、
  「Reset counters now」，feed 連線時另有一行 KPS／最高／總數。點面板外或按 Esc 關閉。
- 面板與設定頁寫同一個設定檔，沒有另外的狀態；完整的按鍵編輯與其他選項在設定頁。
- `barShowKps` 開啟時，feed 連線中圖示旁顯示目前 KPS（水平 bar）。

| 顯示模式（`mode`） | 何時顯示並執行 feed |
|---|---|
| `playing`（預設） | `osu-state` 回報 `playing`，或成績畫面開著（見下） |
| `focused` | `menu`、`playing` 或 `cooldown`（osu! 在前景，或剛打完一首），或成績畫面開著 |
| `always` | 一律 |
| `off` | 永不 |

打完一首後的行為由 `keepAfterPlay` 決定：預設 `results` 讓疊加層在 osu! 成績畫面
（`osu-state.json` 的 `results` 為 `true`）開著的期間一直顯示，feed 也繼續跑，次數、
最高 KPS 與總數留在畫面上，KPS 自然降到 0；`delay` 則不看成績畫面。兩種都在離開想要
的狀態後再停留 `hideDelaySecs` 秒，重打一首（退出再開始）不會閃爍，也不會重啟 feed。
舊版 `osu-state` 沒有 `results` 欄位時視為 `false`，行為等同 `delay`。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | A，零 stock 修改 |
| 系統 | `aulactl`（含 `feed` 子指令）在 shell 的 `PATH` 或設定的路徑；`playing`、`focused` 模式需要 `osu-state` daemon |
| 相容性 | dots-hyprland `446504ad42`、Quickshell `0.3.2` 測試通過 |
| Capabilities | `exec`：執行 `aulactl feed` |

沒有 `osu-state` 狀態檔時 osu! 視為 `off`，`playing` 與 `focused` 模式不會顯示。
`aulactl` 不存在或立刻結束時，模組以 1、2、4 … 最多 30 秒的間隔重試，疊加層顯示
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
| `travelStyle` | `"fill"` | 鍵程畫法：`fill`（填色）、`bar`（右緣長條）、`off` |
| `monitor` | `""` | 顯示的輸出名稱（例如 `eDP-1`），空字串用第一個螢幕 |
| `showCounts` | `true` | 鍵帽下方的次數 |
| `showStats` | `true` | KPS、最高與總數那一行 |
| `barShowKps` | `false` | bar 圖示旁顯示目前 KPS |
| `resetOnSession` | `true` | 每個新 session 歸零計數 |
| `resetRequest` | `0` | 設定頁「Reset counters now」按鈕遞增它；數值本身無意義 |
| `hideDelaySecs` | `3` | 離開想要的狀態後再停留的秒數（0–60） |
| `keepAfterPlay` | `"results"` | `results`：成績畫面開著就一直顯示；`delay`：只停留 `hideDelaySecs` 秒 |
| `depthHz` | `60` | 傳給 feed 的 `--depth-hz`；`0` 用 feed 預設 |
| `binary` | `"aulactl"` | `aulactl` 指令名稱或絕對路徑 |
| `record` | `true` | 每次 feed 執行都錄成 session 檔（`--record --label=<beatmap>`），供 replay 報告使用 |

設定頁有 osu! standard（`KeyZ,KeyX`）、mania 4K（`KeyD,KeyF,KeyJ,KeyK`）與
mania 7K（`KeyS,KeyD,KeyF,Space,KeyJ,KeyK,KeyL`）三個快捷按鈕。

## 資料與行為

- feed 的命令列是 `<binary> feed --keys <keys> [--depth-hz <n>] [--record [--label=<beatmap>]]`，
  參數逐一傳遞，不經過 shell。疊加層隱藏時送 SIGTERM；按鍵、`depthHz`、`binary`、
  `record` 或錄製標籤改變時立即重啟。

- feed 非預期結束時以指數退避重啟；收到 `hello`（鍵盤已連線）後退避歸零。
- 次數只算 `press` 事件。KPS 用 feed 的 `t`（毫秒）計算 1 秒滑動視窗，事件之間用
  牆上時鐘推進，所以停手後 KPS 會自然歸零；feed 重啟時視窗清空，次數保留。
- 最高 KPS 在每次按下時取樣；視窗內的數量只會在按下時增加，所以這就是精確最大值。
- session 是「疊加層出現」或「osu! 開始一首新圖」（`playing` 且 `since` 改變）。
  打開成績畫面不算新 session；從成績畫面重打才歸零。
  `resetOnSession` 關閉時只有手動重置才歸零。
- 計數只在記憶體中，不寫檔；shell 重新載入後歸零。
- IPC：`qs -c ii ipc --any-display call aula_keys reset` 歸零，
  `... call aula_keys status` 回傳模式、osu! 狀態、是否顯示、feed 狀態、鍵盤型號、`max_mm` 與計數的 JSON。

## 錄製與 replay 報告

`record` 開啟（預設）時，feed 帶 `--record`，`aulactl` 把每次執行的原始鍵程資料存成
`$XDG_DATA_HOME/aulactl/sessions/` 下的 session 檔，stdout 不變（格式與保留規則見 aulactl
`docs/feed.md`）。標籤是 feed 啟動時 `osu-state` 的 `beatmap`；沒有 beatmap 時不帶
`--label`。

- 疊加層隱藏時標籤跟著 beatmap 走，所以 feed 一啟動就是正確的圖。
- 疊加層還在（重打、或停留期間選了下一首）時，beatmap 改變只在「不在打圖中」或「新的一首
  剛開始」時採用，並重啟 feed 開新檔；打圖途中絕不重啟。
- 打完後匯出 replay（osu!lazer 的 `.osr`），再執行：

```bash
aulactl replay report latest --open
```

## 限制

- `press`/`release` 是 `aulactl` 依鍵程推算的近似值（見 aulactl `docs/feed.md`），
  適合計數與 KPS，不適合判定時間。
- `focused` 模式在 `cooldown` 期間無法分辨 osu! 是否在前景，一律顯示。
- 鍵程條的觸發點只取 `hello` 的 `point`；rapid trigger 的 press/release 距離不畫出來。
- 疊加層只出現在一個螢幕上。
- 設定頁沒有直接跳到本模組的方式，快速設定面板因此也沒有「開啟設定」按鈕。

## 實作說明

| 檔案 | 角色 |
|---|---|
| `main.qml` | window slot：ConfigLoader owner、顯示狀態機、session 重置、IPC、向 `AulaHub.js` 登記 |
| `bar.qml` | bar slot：圖示、狀態色、選用 KPS、hover 提示、點擊開面板（IPC `aula_keys_bar toggle`） |
| `BarPopup.qml` | hover 提示內容 |
| `QuickPanel.qml` | 快速設定面板內容 |
| `PanelShell.qml` | `memory_center/PanelShell.qml` 的副本：貼著 bar 的浮動框、點外面或 Esc 關閉 |
| `AulaHub.js` | `.pragma library` 共享變數：window slot 登記自己，各螢幕的 bar 讀 feed 即時狀態 |
| `KeyFeed.qml` | `aulactl feed` 行程、NDJSON 解析、每鍵 model、計數與退避重啟 |
| `KeyOverlay.qml` | layer-shell 疊加層（Overlay 層、空 mask 讓點擊穿透） |
| `Keycap.qml` | 單顆鍵帽：鍵程填色或長條、觸發點刻痕、按下狀態、對比字色 |
| `OsuWatch.qml` | 精簡自 `osu_indicator/OsuState.qml` 的狀態檔讀取 |
| `OsuStateLogic.js` | `osu_indicator` 的 vendored 副本，只有檔頭不同 |
| `AulaKeysLogic.js` | 純函式（含 `results` 欄位解析，避免改動 vendored 的 `OsuStateLogic.js`）：按鍵清單、行解析、KPS 視窗、顯示狀態機、退避、填色漸層與字色對比 |
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
FEEDER_HOLD="KeyZ:1.70:press,KeyX:0" tests/feeder.sh feed --keys KeyZ,KeyX  # 固定深度，方便截圖
```

`FEEDER_HOLD` 是假 feed 的環境變數；shell 啟動的行程不會帶上它，要用時另寫一個
export 後 `exec` 假 feed 的小包裝腳本，把 `binary` 指向它。
