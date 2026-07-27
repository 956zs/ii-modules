# battery_trend — 電量趨勢與分析

手機級的長期電量歷史（Tier B）。**stock 電池指示器是主要 bar 入口**：
原生 BatteryPopup 會被完整停用，hover 只顯示 battery_trend 的資訊超集，
點擊 stock 電量環直接開啟詳情面板。`showBar` 仍預設為 `false`；它只控制
額外的 3 小時趨勢線藥丸，不影響 stock 指示器、背景取樣或 IPC。

## 緣起

筆電電池到底掉多快、哪天掉最兇、健康度一年衰減多少，桌面上一直沒有
手機「電池」設定頁那種答案。資料其實都在：UPower 有即時狀態，
`/sys/class/power_supply/` 有精確電量、瞬時功耗、設計容量與循環數——
缺的只是有人長期記下來、算出來、畫出來。

## 互動

| 操作 | 效果 |
|---|---|
| stock 電池指示器 hover | **只顯示 battery_trend 替代彈窗**：充電狀態、平滑功耗、回歸法剩餘時間、UPower 對照、健康度/循環及今日耗電/充電摘要；原生 BatteryPopup 不會在底下出現 |
| stock 電池指示器左鍵 | 開/關詳情面板；`clickToShow` 開或關都只執行此動作，不會與 tooltip 競速 |
| 側欄快速開關磁貼（`battery_horiz_075` 圖示） | 可在快速開關編輯模式加入；點擊時關閉側欄並開啟詳情面板 |
| `qs -c ii ipc --any-display call battery_trend toggle` | 切換詳情面板 |
| 額外 bar 元件（選開 `showBar` 後） | 近 3 小時迷你曲線；`showPercent` 開啟時加百分比 |

## 側欄磁貼

進入右側欄快速開關的編輯模式；當設定中沒有 `battery_trend` 時，「未使用」
區會提供一格 `{type: battery_trend, size: 1}` 磁貼，點一下即加入且立即從候選
區消失。不再需要以手動 JSON 作為主要安裝方式；IPC 仍可供腳本使用。

詳情面板由上而下：即時標頭（大字百分比、功耗、兩種時間估計）、24 小時
曲線（0–100 固定刻度；充電段描邊＋面積填色、放電段中性墨色、休眠/關機
斷點以淡色帶＋虛線端點連接，既保持線段可追蹤也不假裝有中間樣本；hover
十字線讀值）、30 天每日最低–最高區間柱＋平均刻度（hover 讀值）、健康趨勢線（設計容量佔比，
縱軸自動放大到資料所在的窄帶並標明刻度）、使用分析（今日/7 天/30 天
在用耗電速率 %/h、循環當量、平均放電深度、常用充電區間）、近期充放電段列表。

顏色跟隨 Material You 主題：充電＝`colPrimary`（正向強調）、放電＝中性
墨色、健康＝警示色調（`colError`）。充電段除色相外還有面積填色作第二
編碼，斷點以位置（空隙＋色帶）表達——色覺缺陷下語意不丟失。

## 資料來源與取樣

歷史資料全部原生（`exec` capability 用於 stock 指示器點擊與側欄磁貼的 IPC 呼叫）：

- **UPower**（`Quickshell.Services.UPower`）：百分比後備、充放電狀態、
  `changeRate`、`timeToEmpty`/`timeToFull`（拿來對照）、電池自動偵測
  （`nativePath`）
- **sysfs**（FileView 直讀 `/sys/class/power_supply/<bat>/`）：精確電量
  （`energy_now/energy_full`，或 `charge_now/charge_full` 家族——兩種
  單位族都支援，`charge_*` 機型功耗以 `current_now × voltage_now` 求得）、
  設計容量、`cycle_count`

取樣：常駐實例（非單例）每 60 秒（可調 15–600）取一次樣，插拔電源／
狀態翻轉時立即補一樣本，讓充放電段的邊界落在事件上而不是最多一分鐘後。
彈窗/面板開啟時另以 3 秒節奏刷新即時數字（不入歷史）。

多螢幕：bar slot 每個螢幕都會實例化，但歷史檔只能有一個寫入者——
第一個螢幕的實例當選 primary（取樣＋落盤＋補齊設定預設值＋註冊 IPC
target），其餘實例以讀者模式跑，跟著設定檔的 watchChanges 重建畫面。

`showBar: false`（預設）只把根元件設為不可見（layout 會整個跳過，
不留幽靈邊距）——底下的 ConfigLoader、取樣邏輯、IPC handler 照常
實例化，歷史一秒都不斷。bar 入口是「掛載點」而不是「畫面」。

## 保留策略（分層降採樣）

| 層 | 保留 | 粒度 | 內容 |
|---|---|---|---|
| raw | 24 小時 | 取樣間隔 | `[t, %, W, 狀態]`（迷你曲線、24h 圖、回歸估計的原料） |
| hourly | 30 天 | 1 小時 | min/max/avg %、放電平均 W、充電時間佔比、在用耗電 %、在用秒數 |
| daily | 365 天 | 1 天 | 同上（30 天區間圖與長期統計的原料） |
| health | 365 天 | 1 天 | `full/design` %、循環數（每日一張快照） |
| sessions | 最近 120 段 | 事件 | 插電/拔電交替段：種類、起訖時間、起訖 % |

換層在整點/跨日的第一個樣本觸發：把累計器定稿進上一層並立即落盤
（key 與值同 blob 旅行，不存在「新 key 配舊值」的視窗）。整個歷史是
**單一 JSON 字串**（`histState`）、單次賦值寫入、每分鐘至多一次——
分欄位儲存會在熱重載時被讀到撕裂快照（network_traffic 的教訓，見其
README）；JsonAdapter 內宣告 `property var` 會讓 quickshell 段錯誤，
所以是字串。粗估檔案上限 ~100 KB。

休眠/關機表現為相鄰樣本的牆鐘跳躍（> 3× 取樣間隔）：圖上斷線＋淡色帶，
且該段掉電**不計入**在用耗電速率——%/h 才不會被幾小時休眠稀釋。

## 分析公式

- **平滑功耗**：sysfs 瞬時 W 的 EMA（α=0.3）
- **剩餘時間**：對最近 30 分鐘、同狀態、無斷點的 raw 樣本做最小平方
  線性回歸，斜率外推到 0%（或 100%）；樣本 < 5 或斜率方向不對時誠實
  顯示「量測中」。彈窗同時列出 UPower 的原生估計作對照
- **在用耗電速率**：清醒且放電的相鄰樣本 % 差之和 ÷ 清醒放電時數
- **循環當量**：清醒放電 % 累計 ÷ 100
- **健康**：`full/design`；趨勢列 30 天差與全記錄跨度差（百分點）
- **平均放電深度**：拔電段（≥10 分鐘、掉 ≥3%）的起訖 % 差平均
- **常用充電區間**：插電段起始 % 平均 → 結束 % 平均（例如 25% → 85%）

## 安裝

```bash
iimod validate battery_trend/
iimod check battery_trend/
iimod install battery_trend/ --allow-patches   # 磁貼補丁需要 --allow-patches
```

## 設定

`~/.config/illogical-impulse/modules/battery_trend.json`：

| Key | 預設 | 說明 |
|---|---|---|
| `showBar` | `false` | 顯示 bar 元件（stock bar 已有電池指示器，預設不佔 bar 空間；無論開關取樣與歷史照常） |
| `showPercent` | `false` | `showBar` 開啟時在 bar 加百分比文字（stock 指示器已有數字，預設不重複） |
| `samplingIntervalSec` | 60 | 取樣間隔（秒，15–600） |
| `keepHourly` | `true` | 保留 30 天小時級歷史 |
| `keepDaily` | `true` | 保留 365 天日級歷史與健康快照 |
| `keepSessions` | `true` | 記錄充放電段 |
| `batteryName` | `auto` | sysfs 電池名；`auto` 走 UPower `nativePath`，再退回探測 BAT0/BAT1/… |

升級注意：設定檔裡已經有 `showBar` 的既有使用者維持自己的選擇（模塊
只補缺失的 key，不覆寫既有值）；全新安裝預設沒有 bar 元件。

`histState` 是模塊自管的歷史 blob（上表五層），非使用者設定。
全部選項在設定 app 的 **Modules → Battery Trend** 頁有對應控件。

## 實作說明（給模塊作者的參考）

- `BatteryLogic.qml`：取樣＋累計＋分析**實例**（非單例），由 `bar.qml`
  建立並向下傳遞；`sampling` 旗標區分 primary（寫）與 reader（讀）模式
- `ConfigLoader.qml`：FileView＋JsonAdapter 寫自己的設定檔；`ready`
  旗標讓歷史初始化等檔案真正載入；`owner` 綁 primary 當選，遲到的當選
  會補 `writeAdapter()`
- `TrendGraph.qml`：時間軸感知的迷你曲線——X 是牆鐘時間（10 分鐘的
  資料不會被拉滿整幅）、斷點斷線、充電段換色；Y 用留白 min–max 窗
  （最小跨度 8 個百分點），固定 0–100 會把正常的下午壓成直線
- `DayChart.qml` / `BandChart.qml` / `HealthChart.qml`：Canvas 圖表，
  皆含 hover 讀值；軸線用 `colOutlineVariant` 退居背景，文字一律用
  文字墨色（不用系列色染文字）
- sysfs 單位族偵測一次定案（energy_* 優先，退 charge_*），之後每 tick
  只 reload 命中的那一族；`readInstant()` 同時服務取樣與快速輪詢
- `StockBatteryPopup.qml`：stock 指示器所建立的模塊自有替代包裝；內含
  `owner:false`、`sampling:false` 的 reader ConfigLoader/BatteryLogic，絕不成為
  第二個記帳寫入者；`clickToShow` 模式下停用 hover 視窗，點擊前也先抑制彈窗
- Tier B 補丁全部 insert-only：BatteryIndicator 加 alias import、唯一 click IPC、
  模塊替代 popup，並把原生 BatteryPopup 的 `active` 固定為 false；另在
  AndroidToggleDelegateChooser 加磁貼 delegate，以及在 AndroidQuickPanel 的
  `id: unusedRows` 後加入缺席時的 edit-mode 候選。所有錨點都有精確 probe
- 每個用到的 stock API（BarGroup、StyledPopup、StyledPopupValueRow、
  StyledRectangularShadow、Config* 控件、GlobalStates、BatteryIndicator/BatteryPopup、
  兩個側欄補丁錨點與磁貼元件）都在 manifest 宣告探針
