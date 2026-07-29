# clock_popup_slim - Bar 時鐘客製化（實驗性 Tier B）

> [!WARNING]
> **實驗性／可能棄用**：此模塊以 Tier B 補丁依賴目前 stock bar 的中央群組結構。
> 若上游重做該版面，或 repository 提供更安全的替代方案，本模塊可能停止維護並棄用。
> 安裝與下載目前仍保留，但不應視為穩定介面。

客製化水平 bar 中央時鐘的顯示內容與密度。技術 ID 保留為
`clock_popup_slim`，因此既有「精簡時鐘彈窗」安裝可以原地升級；使用者可見名稱自
2.0.0 起改為「Bar 時鐘客製化」。2.1.0 新增對稱中央區寬度設定，用來減少工作區
左右的空白，同時保持工作區位於螢幕正中央。

## 可調整項目

- 只顯示時間，或顯示時間、分隔符與日期
- Qt 時間格式，例如 `HH:mm`、`hh:mm AP`、`HH:mm:ss`
- Qt 日期格式，例如 `ddd, dd/MM`、`MM/dd`
- 分隔符、內容間距、時鐘左右留白
- 對稱調整工作區左右兩個中央區域的寬度（280–360 px）
- 時間與日期的文字尺寸偏移
- hover 彈窗是否隱藏 System uptime 與 To Do

預設值是只顯示 `HH:mm`、時鐘左右留白 0 px、中央左右區域各 280 px，並維持原模塊的精簡 hover。加入 `:ss`
時，模塊會自動把自己的時鐘更新精度提高到每秒；不會改動 shell 的全域時間設定。

目前只替換水平 bar 的 `ClockWidget`。垂直 bar 的堆疊式時鐘維持 stock 版面，以免自訂
單行格式破壞其固定寬度設計。

設定儲存在：

```text
~/.config/illogical-impulse/modules/clock_popup_slim.json
```

模塊不寫入 shell 的 `config.json`，因此鎖定畫面、桌面時鐘和其他使用全域
`DateTime.time` 的元件不受影響。

## 安裝

```bash
iimod validate modules/clock_popup_slim/
iimod check    modules/clock_popup_slim/
iimod install  modules/clock_popup_slim/ --allow-patches
```

安裝後在 Settings > Modules > Bar 時鐘客製化調整選項。

要完全回到 stock 時鐘與完整 popup：

```bash
iimod disable clock_popup_slim
```

重組引擎會從乾淨基底移除本模塊的所有圍欄補丁。

## 實作說明

IIMP v1 的 bar slot 只能加入額外元件，不能替換位於 stock 中央群組內的既有時鐘；本模塊
因此是 Tier B：

- 在 `BarContent.qml` 匯入模塊元件、隱藏 stock `ClockWidget`，並在相同 layout 位置插入
  `ClockBar`。
- 在 `ClockWidgetPopup.qml` 插入唯讀設定載入器，讓 uptime 與 To Do 的可見性即時跟隨
  `slimPopup`。
- 所有修改都是 insert-only，沒有內嵌或取代 stock 檔案。
- 每個補丁錨點都有精確 `file-contains` probe；上游改寫導致錨點失效時，安裝或 `reapply`
  會以相容性／錨點錯誤停止，不會靜默套出半套。
