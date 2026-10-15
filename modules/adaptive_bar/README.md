# adaptive_bar - 自適應 Bar 版面

Tier B 模塊，讓水平 bar 在 16:10 等較窄螢幕上不再互相重疊。右側空間不足時，
先把釘選系統匣圖示收進系統匣溢位選單，再對稱縮窄中央兩側區塊；21:9 等寬螢幕維持
stock 版面。只處理水平 bar，垂直 bar 不受影響。

> [!IMPORTANT]
> 本模塊以 insert-only patches 修改 stock `BarContent.qml` 與 `SysTray.qml`，
> 安裝需要 `--allow-patches`。建議搭配 `iimod` 1.4.0 以上（host generation 3），
> 舊 host 會讓隱藏中的 bar 模塊仍佔用寬度，使本模塊多收系統匣圖示。

## 功能

stock 水平 bar 的中央區固定置中，右側區只能使用中央區到螢幕邊緣之間的寬度。
內容超出時，stock RTL `RowLayout` 會往左溢出、壓到時鐘群組。本模塊在每個螢幕的
bar 內依序退讓：

| 順序 | 動作 | 還原條件 |
|---|---|---|
| 1 | 由靠近 `⌄` 的一端開始，把釘選系統匣圖示收進溢位選單 | 空間多出 8 px 以上 |
| 2 | 左右中央區塊同步縮窄，最多縮到內容所需寬度 | 空間多出 8 px 以上 |
| 3 | 仍放不下時裁切右側區，不再蓋到中央區 | 空間足夠時自動取消 |

- 工作區永遠維持在螢幕正中央；時鐘群組不會被縮到比內容還窄。
- 收合的圖示排在溢位選單最前面，左鍵、右鍵與選單行為與 stock 相同。
- 螢幕寬度、系統匣圖示數量或 bar 模塊寬度改變時自動重算。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | B，七個 insert-only patches |
| 相容性 | dots-hyprland `446504ad42`、Quickshell `0.2.1` 測試通過 |
| `iimod` | 1.4.0 以上建議；舊版仍可安裝，但隱藏模塊的寬度會被算進需求 |
| Capabilities | 無；不執行外部命令 |

`compat.probes` 會檢查所有錨點與用到的 stock id。上游改動版面時
`iimod check` 或 `reapply` 會停止，不會只套用一部分。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/adaptive_bar/
iimod check modules/adaptive_bar/
iimod install modules/adaptive_bar/ --allow-patches
```

暫時回到 stock 版面：`iimod disable adaptive_bar`；完整移除：
`iimod uninstall adaptive_bar`。

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/adaptive_bar.json`，也可在
**Settings > Modules > 自適應 Bar 版面** 調整。

| Key | 預設 | 說明 |
|---|---|---|
| `centerSideMaxWidth` | `360` | 左右中央區塊寬度上限（190-360 px）。`360` 等於 stock 寬度；實際上限取它與 stock 響應寬度的較小值 |

即使空間充足，中央區塊也不會超過這個上限；空間不足時仍會再往下縮。

## 資料與行為

- 不寫入 shell `config.json`，也不修改 `tray.pinnedItems`；收合只影響顯示。
- 每個螢幕的 bar 各自計算，多螢幕不同解析度互不影響。
- 輸入變動後等 40 ms 讓 layout 穩定再重算，Revealer 動畫結束前不會反覆調整。

## 限制

- 只處理水平 bar；垂直 bar 與 stock 1200 px 以下的精簡模式維持 stock 行為。
- 系統匣溢位選單停用（`showOverflowMenu: false`）時不收合圖示，直接進入縮窄步驟。
- 中央左側區塊的最小寬度假設 Media 標題可省略到約 96 px。
- `clock_popup_slim` 3.0.0 起不再調整中央寬度；更舊版本與本模塊同時啟用時，兩者
  會綁定同一屬性，結果不可預期。

## 實作說明

| Patch surface | 行為 |
|---|---|
| `BarContent.qml` import | 載入 `FitController` |
| `centerSideModuleWidth` 後 | 每個 bar 一個 `FitController`；兩個中央區塊的 `implicitWidth` 與右側區 `clip` 由它決定 |
| 水平 `SysTray` 實例 | 加上 id 並傳入收合數 |
| `SysTray.qml` root | 收合狀態，以及溢位模型、溢位按鈕與 popup 的條件式 `Binding` |
| 釘選 delegate | `index` 小於收合數時隱藏 |
| 溢位 grid / repeater | 收合時改用「收合圖示 + 原溢位圖示」模型與欄數 |

規劃邏輯在純函式 `Fit.js`：先以目前收合數把量到的右側需求還原成未收合需求，
再計算最少收合數與縮窄量。退讓只有在需求減少超過 8 px 時才還原，避免文字寬度
微幅變動造成圖示閃爍。沒有收合時，`SysTray.qml` 的條件式 `Binding` 全部失效，交回 stock 綁定。

## 開發

```bash
node --test modules/adaptive_bar/tests/*.test.mjs
iimod validate modules/adaptive_bar/
iimod i18n check modules/adaptive_bar --locale zh_TW --locale zh_CN --deny-orphans
iimod check modules/adaptive_bar/
```
