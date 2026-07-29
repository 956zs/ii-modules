# Battery Trend - 電量趨勢

Tier B 長期電量歷史與分析模塊。stock 電池指示器是主要入口：原生 popup 由
Battery Trend 的資訊超集取代，點擊電量環會開啟詳細面板。

可選的 3 小時 bar sparkline 預設關閉。`showBar` 不影響 stock 指示器、背景取樣、
側欄磁貼或 IPC。

## 互動

| 入口 | 效果 |
|---|---|
| Hover stock 電池指示器 | 顯示充電狀態、平滑功耗、時間估計、健康度與今日摘要 |
| 左鍵點擊 stock 電池指示器 | 切換詳細面板 |
| 側欄快速開關磁貼 | 關閉側欄並開啟詳細面板 |
| `qs -c ii ipc --any-display call battery_trend toggle` | 切換詳細面板 |
| 可選 bar 元件 | 顯示近 3 小時曲線；可加百分比 |

快速開關編輯模式會在磁貼缺席時，於「未使用」區提供 `battery_trend`。點擊即可
加入，無需手動修改 `config.json`。

## 詳細面板

| 區塊 | 內容 |
|---|---|
| 即時標頭 | 百分比、平滑功耗、回歸估計與 UPower 原生估計 |
| 24 小時 | 充放電曲線、休眠／關機斷點與 hover 讀值 |
| 30 天 | 每日最低－最高區間、平均刻度與 hover 讀值 |
| 健康趨勢 | 設計容量占比、循環數與窄幅自適應刻度 |
| 使用分析 | 今日／7 天／30 天耗電速率、循環當量、放電深度與充電區間 |
| 近期 sessions | 近期插電／拔電段的起訖時間與電量 |

顏色跟隨 Material You。充電使用 `colPrimary`，放電使用中性色，健康趨勢使用
`colError`；充電區段另以面積填色、斷點以空隙和淡色帶表達，不只依賴色相。

## 需求與權限

模塊不需要額外系統 package。資料來自 Quickshell UPower service 與
`/sys/class/power_supply`。

| 整合 | 用途 |
|---|---|
| Tier B stock battery patches | 取代 hover popup，將 stock 指示器點擊導向模塊面板 |
| Tier B sidebar patches | 提供磁貼 delegate 與編輯模式新增／重新加入列 |
| `exec` capability | 僅供側欄磁貼以 `execDetached` 呼叫 `qs ... ipc` |

stock 指示器點擊直接呼叫模塊 QML，不經 `exec`。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/battery_trend/
iimod check modules/battery_trend/
iimod install modules/battery_trend/ --allow-patches
```

## 設定

設定檔位於：

```text
~/.config/illogical-impulse/modules/battery_trend.json
```

| Key | 類型 | 預設 | 範圍／選項 | 說明 |
|---|---|---:|---|---|
| `showBar` | boolean | `false` | - | 顯示額外 bar sparkline |
| `showPercent` | boolean | `false` | - | sparkline 旁顯示百分比 |
| `samplingIntervalSec` | integer | `60` | 15-600 秒 | 歷史取樣間隔 |
| `keepHourly` | boolean | `true` | - | 保留 30 天小時級歷史 |
| `keepDaily` | boolean | `true` | - | 保留 365 天日級歷史與健康快照 |
| `keepSessions` | boolean | `true` | - | 保留近期充放電 sessions |
| `batteryName` | string | `auto` | sysfs 名稱或 `auto` | 指定電池；自動模式優先採 UPower `nativePath` |

既有設定檔中的 `showBar` 會保留原值；只有缺少該 key 的新安裝使用 `false`。
`histState` 是模塊管理的內部歷史 blob，不是一般使用者設定。

## 資料來源與取樣

| 來源 | 用途 |
|---|---|
| Quickshell UPower | 狀態、百分比 fallback、`changeRate`、時間估計與電池偵測 |
| sysfs `energy_*` | 精確能量、容量與功耗 |
| sysfs `charge_*` + `voltage_now` | 不提供 `energy_*` 機型的容量與功耗 fallback |
| `cycle_count` | 循環數與健康歷史 |

primary bar instance 每 60 秒取樣一次，插拔電源或充放電狀態變化時立即補樣。
Popup／面板開啟期間的 3 秒刷新只更新即時數字，不寫入歷史。

每個螢幕都有 bar instance，但只有第一個螢幕的 primary 負責取樣、寫盤、補齊設定
預設與 IPC。其他 instance 以 watched-reader 模式顯示同一份資料。

`showBar: false` 只隱藏版面；ConfigLoader、取樣與 IPC 仍持續運作，不留下 bar
空白。這讓 stock 電池環保留主要入口，同時避免重複占用 bar。

## 保留策略

| 層 | 保留時間 | 粒度 | 主要內容 |
|---|---:|---:|---|
| raw | 24 小時 | 取樣間隔 | 時間、百分比、功耗與狀態 |
| hourly | 30 天 | 1 小時 | min/max/avg、功耗、充電占比與在用耗電 |
| daily | 365 天 | 1 天 | 長期區間與耗電統計 |
| health | 365 天 | 1 天 | `full/design` 與循環數 |
| sessions | 最近 120 段 | 事件 | 充放電種類、起訖時間與百分比 |

歷史以單一 JSON 字串 `histState` 寫入，避免熱重載時讀到跨欄位撕裂快照。整點或
跨日的第一個樣本會先定稿上一層，再立即寫盤；一般取樣寫入會節流。

相鄰樣本間隔超過三倍取樣週期時視為休眠或關機斷點。圖表會顯示斷線，且該段
電量差不納入「在用耗電速率」。

## 分析語意

- **平滑功耗**：sysfs 瞬時功耗的 EMA，`alpha = 0.3`。
- **剩餘時間**：最近 30 分鐘、同狀態且無斷點樣本的最小平方法回歸；少於五個
  樣本或斜率方向不合理時顯示「量測中」。
- **在用耗電速率**：清醒放電期間的百分比差，除以清醒放電時數。
- **循環當量**：清醒放電百分比累計除以 100。
- **健康**：目前 full capacity 除以 design capacity。
- **平均放電深度**：至少 10 分鐘且下降至少 3% 的拔電 sessions。
- **常用充電區間**：插電 sessions 的平均起始百分比到平均結束百分比。

## 限制

- sysfs 欄位依硬體與 kernel driver 而異；缺少必要欄位時使用 UPower fallback，
  不會捏造健康度或功耗。
- 剩餘時間是近期趨勢外推，不是保證值；負載快速改變時會隨新樣本調整。
- 關機與休眠期間沒有中間樣本，模塊只標示斷點，不猜測過程。
- Tier B patches 依賴目前 stock battery 與 sidebar anchors；上游改動時
  `iimod check` 會拒絕安裝。

## 實作說明

| 檔案 | 職責 |
|---|---|
| `BatteryLogic.qml` | primary/reader lifecycle、取樣、累計與分析 |
| `ConfigLoader.qml` | 設定與單一歷史 blob 持久化 |
| `StockBatteryPopup.qml` | stock 指示器使用的模塊 popup 與 detail-panel 入口 |
| `TrendGraph.qml` | 時間軸感知的 3 小時 sparkline |
| `DayChart.qml` | 24 小時充放電與斷點圖 |
| `BandChart.qml` | 30 天最低－最高區間圖 |
| `HealthChart.qml` | 健康趨勢圖 |

所有 patches 都是 insert-only。卸載或停用後，IIMP 會從乾淨基底還原 stock popup
與點擊行為。

## 卸載與資料

```bash
iimod uninstall battery_trend
```

卸載會還原 stock 電池 UI 並移除 sidebar integration，但不刪除歷史設定檔。需要完全
移除資料時，再由使用者刪除：

```text
~/.config/illogical-impulse/modules/battery_trend.json
```
