# Bar 時鐘客製化（實驗性）

> [!WARNING]
> 這是依賴目前 stock bar 中央群組結構的 Tier B 模塊。若上游重做該版面，
> 或 repository 提供更安全的替代方案，本模塊可能停止維護並棄用。

客製化水平 bar 的時間／日期格式、密度與 hover popup。技術 ID 保留為
`clock_popup_slim`，既有精簡時鐘彈窗安裝可原地升級。

## 功能

- 只顯示時間，或顯示時間、分隔符與日期。
- 使用 Qt time/date format，例如 `HH:mm:ss`、`hh:mm AP`、`ddd, dd/MM`。
- 調整內容間距、水平 padding 與時間／日期字級偏移。
- 以相同上限調整工作區左右的中央區寬度，保持 workspaces 在螢幕中央。
- 選擇是否在共用 stock popup 隱藏 System uptime 與 To Do。
- 時間格式包含未被引號包住的 seconds token 時，以每秒精度更新模塊時鐘。

## 設定

設定檔位於：

```text
~/.config/illogical-impulse/modules/clock_popup_slim.json
```

預設只顯示 `HH:mm`、水平 padding 為 `0`，並啟用精簡 popup。
`centerSideWidth` 可設為 280-360 px；它是左右兩側的上限，不是固定寬度。
實作使用 `Math.min(stockResponsiveWidth, centerSideWidth)`，所以較窄 viewport 仍由
stock responsive width 決定。

模塊不修改 shell `config.json` 或全域時間格式。Lock screen、桌面時鐘與其他使用
`DateTime.time` 的元件不受影響。

## 適用範圍與限制

- 自訂 time/date layout 只取代水平 bar 的 `ClockWidget`。
- 垂直 bar 保留 stock 堆疊式時鐘，避免單行格式破壞固定寬度版面。
- `slimPopup` 修改水平與垂直 bar 共用的 stock popup visibility。
- 中央區寬度依賴目前 `leftCenterGroup` 與 `rightCenterGroup` 結構。
- 模塊沒有 capabilities，也不執行外部命令。

| 相容性 | 值 |
|---|---|
| Tested dots commit | `446504ad42` |
| Tested Quickshell | `0.2.1` |
| Tier | B，九個 insert-only patches |

錨點或 probes 因上游改動而失效時，`iimod check` 或 `reapply` 會停止，不會靜默
套用部分客製化。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/clock_popup_slim/
iimod check modules/clock_popup_slim/
iimod install modules/clock_popup_slim/ --allow-patches
```

安裝後在 **Settings > Modules > Bar 時鐘客製化** 調整選項。

## 停用與卸載

暫時回到 stock 時鐘與完整 popup：

```bash
iimod disable clock_popup_slim
```

完整卸載：

```bash
iimod uninstall clock_popup_slim
```

IIMP 會從乾淨基底重組 stock QML。設定檔會保留，重新安裝時可繼續使用。

## 實作說明

| Patch surface | 行為 |
|---|---|
| `BarContent.qml` import | 載入模塊元件 |
| stock `ClockWidget` | 隱藏 stock instance，在相同 layout 位置插入 `ClockBar` |
| 左右中央群組 | 以兩個對稱 `Binding` 套用相同 responsive width 上限 |
| `ClockWidgetPopup.qml` import/reader | 載入 readonly `ConfigLoader` |
| Uptime / To Do | 以兩個 visibility patches 跟隨 `slimPopup` |

所有變更都是 insert-only，沒有內嵌或取代 stock 檔案。

## 開發驗證

```bash
node --test modules/clock_popup_slim/tests/*.test.mjs
iimod validate modules/clock_popup_slim/
iimod suggest modules/clock_popup_slim/
iimod check modules/clock_popup_slim/
```
