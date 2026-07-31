# Screen Time - 螢幕使用時間

手機風格的焦點使用時間統計，提供 Daily 與 Trends 兩個詳情頁、30 天可瀏覽歷史、
bar 摘要與獨立的 AI 工作時長。焦點記帳使用 Quickshell `ToplevelManager`；鎖屏與
休眠斷層不計入。

側欄磁貼是可選的 Tier B integration，由 delegate 與 edit-mode re-add 兩個
insert-only patches 組成。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/screentime/
iimod check modules/screentime/
iimod install modules/screentime/ --allow-patches
```

## 入口與操作

詳情面板分成「每日／趨勢」兩頁。

| 入口 | 效果 |
|---|---|
| Hover bar 藥丸 | 顯示今日總時長、Top 5 與昨日比較 |
| 點擊 bar 藥丸 | 開啟詳細面板 |
| 側欄快速開關磁貼 | 關閉側欄並開啟詳細面板 |
| `qs -c ii ipc --any-display call screentime toggleDetails` | 切換詳細面板 |

按 `Esc` 或點擊面板外部可關閉詳細面板。

## Daily

Daily 可用前一天／後一天瀏覽最近 30 個日曆日。選定日期會更新總時長、應用排行
與 AI 工作摘要；點擊中央日期可回到今日。沒有紀錄的日期顯示空狀態，不會當成零值。

24 小時直方圖刻意只在今日 Daily view 顯示。v1.3 起，完整日紀錄會保存
`hours[24]`；這些歷史時段資料用於 Trends heatmap，而不是在過去日期的 Daily view
重複顯示。

## Trends

- 最近 7 個完整日中有紀錄日期的平均，附 `N/7` 覆蓋率。
- 與前一個 7 日完整期間比較。
- 缺日不冒充零值的 7 日柱狀圖與 30 日曲線。
- 最近 28 個完整日的星期×時段熱力圖（星期一至星期日 x 24 小時）。

舊版歷史沒有 `hours[24]` 時，仍可參與每日總量平均，但不會被視為有時段明細。
Heatmap 以 `N/28` 顯示實際覆蓋率，支援 hover 讀值、Tab focus 與方向鍵瀏覽。

圖表使用 Material You `colPrimary` 單色階，換主題時會重繪；數值與身分由文字和
位置承載，不只依賴色相。

## 焦點記帳語意

- **事件驅動**：焦點切換時，把經過的牆鐘秒數記給上一個應用。
- **心跳**：每 15 秒結算長時間不切換的同一應用，也用來辨識 suspend gap。
- **鎖屏**：`GlobalStates.screenLocked` 為真時不入帳。
- **休眠／掛起**：事件間隔超過 `idleGapSec` 時不計該段。
- **無焦點**：空桌面不入帳，因此今日總時長等於各應用時長總和。
- **應用名稱**：優先使用本機 desktop entry 名稱；Steam `steam_app_<id>` 會從
  desktop entry 的 `steam://rungameid/<id>` command 尋找遊戲名稱，不執行網路
  查詢。無法解析的反向網域 app ID 取最後一段，一般視窗 class 則保留完整名稱與
  版本資訊，例如 `Minecraft* 1.20.1` 顯示為 `Minecraft 1.20.1`。

沒有 idle protocol 資料時，螢幕未鎖但人已離開且仍有焦點視窗的時間會繼續入帳。
正常 component destruction 會先結算並寫盤；突然 crash 或強制終止仍可能遺失最近
一次週期寫入後、最多約一分鐘的時間。

記帳者只有 window slot 的 `main.qml`。每個螢幕的 bar instance 都是純 reader，
避免多螢幕重複累加；代價是 bar 數字可能落後最多一次週期寫入。

## AI 工作時長

AI 維度回答「agent processes 實際工作多久」，與「視窗聚焦多久」分開記錄，
兩者不相加。

每 10 秒掃描一次 `/proc`。符合 `aiProcessRegex` 的 process 會形成候選 session；
若符合項目巢狀於另一個符合 process，整棵 process tree 歸入最外層 session root，
避免重複計數。

當取樣窗內 process tree CPU 使用率達到 `aiActiveCpuPct` 門檻時，該 session 視為
工作中。這是可調 heuristic：純網路等待且本機 CPU 沒有活動時，可能被判定為閒置。

- 主數字是至少一個 session 工作中的 wall-clock 聯集。
- 另記錄並行峰值與各 sessions 的時間總和。
- 鎖屏期間照常計算 AI 工作時間。
- Suspend 造成的長斷層只重建 baseline，不入帳。
- 關閉 `aiTracking` 會停止取樣 process。

## 側欄磁貼

首次加入時，將以下項目放入
`~/.config/illogical-impulse/config.json` 的
`sidebar.quickToggles.android.toggles`：

```json
{"type": "screentime", "size": 1}
```

設定頁提供可複製的同一行。磁貼之後若在 edit mode 移除，會出現在「未使用」區，
可直接點擊重新加入；不需要再次手動修改 JSON。

卸載後殘留的 `screentime` toggle 會被 stock delegate 忽略。建議卸載時一併從
quick-toggle config 移除。

## 設定

設定檔位於：

```text
~/.config/illogical-impulse/modules/screentime.json
```

| Key | 預設 | 說明 |
|---|---:|---|
| `excludedApps` | `""` | 逗號分隔的 appId/class 子字串，不分大小寫 |
| `idleGapSec` | `90` | 超過此秒數的事件間隔視為 suspend/idle gap |
| `keepHistory` | `true` | 保留 30 天歷史；關閉時清除歷史，只記今日 |
| `aiTracking` | `true` | 啟用 AI process-tree 取樣 |
| `aiProcessRegex` | `^(claude\|codex)$` | 匹配 process `comm` 的 regular expression |
| `aiActiveCpuPct` | `1` | 工作判定門檻，單位為單核 CPU 百分比 |

全部公開選項都可在 **Settings > Modules > Screen Time** 調整。

## 資料與保留

`histState` 是模塊管理的單一 JSON 字串，包含今日應用秒數、今日每小時資料、AI
資料與最近 30 天 daily records。單 blob 寫入避免熱重載時讀到跨欄位撕裂快照。

每個 daily record 最多保留 Top 20 應用，其餘摺疊成「其他」。v1.3 起，只有經過
完整日收尾且標記 `hoursComplete` 的 `hours[24]` 會進入 heatmap；中途升級的當天
不會把不完整時段冒充完整日。

## 限制

- 沒有 idle protocol 時，未鎖屏 AFK 無法與實際使用區分。
- AI CPU threshold 是 heuristic，不是 agent protocol；低 CPU 的遠端等待可能漏算，
  其他符合 regex 的高 CPU process 也可能被計入。
- 舊 daily records 缺少 hourly data 時不參與 heatmap，但仍參與總量統計。
- 30 天瀏覽以已保存 records 為準，缺日保持 unknown，不補零或插值。
- Sidebar integration 依賴目前 stock quick-toggle anchors；上游改動時
  `iimod check` 會拒絕套用。

## 實作說明

| 檔案 | 職責 |
|---|---|
| `ScreentimeLogic.qml` | 焦點／鎖屏／排除規則、歷史 fold 與持久化 |
| `AgentMonitor.qml` | `/proc` process-tree CPU heuristic |
| `HistoryLogic.js` | 日期、完整期間、missing semantics 與 heatmap 累計 |
| `DetailsPanel.qml` | Daily/Trends navigation 與 panel interaction |
| `ColumnChart.qml` / `LineChart.qml` | missing-aware period charts |
| `HourHeatmap.qml` | 7 x 24 heatmap、鍵盤與 accessibility 狀態 |
| `Format.qml` | 時長與本機應用名稱格式化 |
| `ConfigLoader.qml` | 設定與單一歷史 blob |

兩個 Tier B patches 分別新增 sidebar tile delegate，以及磁貼缺席時的 edit-mode
unused-row offer。`exec` capability 只用於磁貼的 argv-safe `qs ... ipc` 呼叫。
Manifest probes 覆蓋相容性關鍵的 stock integration surfaces 與 patch anchors。

## 開發驗證

```bash
node --test modules/screentime/tests/*.test.mjs
for file in modules/screentime/*.qml; do qmlformat "$file" >/dev/null; done
iimod validate modules/screentime/
iimod suggest modules/screentime/
iimod check modules/screentime/
```
