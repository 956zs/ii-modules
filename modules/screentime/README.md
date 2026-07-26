# screentime — 螢幕使用時間

手機風格的螢幕使用時間統計（Tier B：一個側欄磁貼補丁）。以 Quickshell 原生
`ToplevelManager` 做前台焦點記帳：今日各應用時長、每小時直方圖、7 天趨勢、
30 天每日曲線。

## 互動

| 入口 | 效果 |
|---|---|
| bar 藥丸（`timelapse` 圖示＋「6h 23m」） | hover：彈窗（今日總時長、Top 5 應用比例條、昨日比較）；點擊：開啟詳情面板 |
| 側欄快速開關磁貼（沙漏圖示，見下方設定） | 點擊：關閉側欄並開啟詳情面板 |
| `qs -c ii ipc --any-display call screentime toggleDetails` | 切換詳情面板 |

詳情面板：今日總時長與昨日比較、今日 24 小時直方圖（當前小時高亮）、
最近 7 天趨勢（今日高亮、其餘用同色淺階）、應用排行（時長＋比例條）、
30 天每日曲線。圖表全部單色（Material You `colPrimary`，換壁紙自動變），
hover 任一柱/點會在圖上方讀出該時段數值。Esc 或點擊外部關閉。

## 側欄磁貼（必讀：需手動加一行設定）

內建磁貼編輯器只提供原生類型，**不會**列出本模塊的磁貼。安裝後請手動把
下列項目加入 `~/.config/illogical-impulse/config.json` 的
`sidebar.quickToggles.android.toggles` 陣列（`size: 2` 可換寬版，顯示名稱）：

```json
{"type": "screentime", "size": 1}
```

設定 app 的 **Modules → Screen Time** 頁也有這行可直接複製。移除磁貼即從
陣列刪掉該項；`iimod uninstall` 後殘留的該項只會被 DelegateChooser 靜默略過。

## 記帳原則（誠實規則）

- **事件驅動**：每次焦點切換把經過的牆鐘秒數記給「上一個」應用
  （鍵：appId/class）。15 秒心跳只是為了封頂單段間隔——長時間停留同一應用
  也能穩定累計，並讓休眠可被偵測。
- **鎖屏暫停**：`GlobalStates.screenLocked` 為真時完全不入帳。
- **休眠/掛起**：兩次記帳事件之間牆鐘跳躍超過門檻（預設 90 秒，可調）的
  時段不入帳。
- **已知限制**：螢幕沒鎖、視窗有焦點但人離開（AFK）無法從 shell 偵測
  （沒有 idle 協議來源），這段會照常入帳。shell 重啟會丟失最後一次寫盤
  （≤1 分鐘）之後的時間。無視窗焦點（空桌面）不入帳，故「今日總時長」＝
  各應用之和。

記帳者只有一個：window slot 的 `main.qml`（模塊 host 只實例化一次）。
bar 元件是純讀者——bar 每個螢幕各實例化一份，放記帳會在多螢幕下重複計算；
代價是 bar 數字最多滯後一次寫盤（≤1 分鐘），與顯示粒度（分鐘）相稱。

## 安裝

```bash
iimod validate screentime/
iimod check screentime/
iimod install screentime/ --allow-patches   # 磁貼補丁需要 --allow-patches
```

## 設定

`~/.config/illogical-impulse/modules/screentime.json`：

| Key | 預設 | 說明 |
|---|---|---|
| `excludedApps` | `""` | 逗號分隔的 appId/class 子字串，命中者不入帳（不分大小寫） |
| `idleGapSec` | `90` | 閒置間隔門檻（秒）；事件間牆鐘跳躍超過此值視為離開 |
| `keepHistory` | `true` | 保留 30 天每日歷史；關閉即清除並只記今日 |

`histState` 是模塊自管的統計狀態（今日各應用秒數＋今日各小時直方圖＋
30 天每日紀錄，每日紀錄含 Top 20 應用、長尾摺疊進「其他」）。整個歷史是
**單一 JSON 字串**、單次賦值寫入——分欄位儲存在熱重載時會被讀到撕裂快照
（network_traffic 的教訓）；單 blob 讓撕裂在結構上不可能。每分鐘至多寫回
一次，不是使用者設定。

全部選項在設定 app 的 **Modules → Screen Time** 頁有對應控件。

## 實作說明（給模塊作者的參考）

- `ScreentimeLogic.qml`：焦點記帳**實例**（非單例——IIMP 模塊禁用 pragma
  Singleton），由 `main.qml` 建立；`focusedApp` 一個 binding 同時折疊
  焦點切換、鎖屏、排除清單三種來源，`onFocusedAppChanged` 先結算舊區間
  再換人
- `ConfigLoader.qml`：FileView＋JsonAdapter 寫自己的設定檔；`owner` 旗標
  讓唯一實例負責 materialise 預設值；**絕不**在 JsonAdapter 裡宣告
  `property var`（quickshell 反序列化會 segfault），map 一律 JSON 字串
- `ColumnChart.qml` / `LineChart.qml`：Canvas 圖表，遵循 dataviz 規格
  （柱 ≤24px、資料端 4px 圓角/基線方角、柱間 2px 空隙、線 2px 圓端、
  面積 10% 透明度、端點 8px 帶 2px 底色環、hover 讀出列）；單一色相承載
  量值，身分由文字標籤承載，數值一律穿文字色 token
- `bar.qml`：BarGroup 藥丸；水平/雙行 bar 用「圖示＋6h 23m」，垂直 bar
  自動改直排緊湊版（圖示上、`6.4h` 下）
- 補丁只有一個：往 `AndroidToggleDelegateChooser.qml` 的
  `roleValue: "antiFlashbang"` 錨點前插入一個完整 `DelegateChoice`
  （`AndroidQuickToggleButton` 是該目錄的本地元件，`Quickshell` 已在檔內
  import；`mainAction` 用 `execDetached` 呼叫本模塊 IPC——這是 manifest
  宣告 `exec` 的原因）。磁貼刻意不讀統計檔：那需要再補一個 import 補丁，
  換來的只是 size-2 磁貼上一行 ≤1 分鐘新鮮度的字
- 每個用到的 stock API（BarGroup、StyledPopup、GlobalStates 的鎖屏/側欄
  狀態、設定控件、補丁錨點與元件）都在 manifest 宣告了探針
