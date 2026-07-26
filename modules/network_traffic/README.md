# network_traffic — IIMP 參考模塊

Bar 上下行流量計（Tier A，零 stock 補丁）。即時速率、開機累計、hover 彈窗含 60 樣本趨勢曲線。

## 安裝

```bash
iimod validate network_traffic/
iimod check network_traffic/
iimod install network_traffic/     # 或先 iimod pack 再裝 .iimod
```

## 設定

`~/.config/illogical-impulse/modules/network_traffic.json`：

| Key | 預設 | 說明 |
|---|---|---|
| `updateInterval` | 2000 | 輪詢間隔（毫秒） |
| `excludeRegex` | `^(lo\|docker.*\|veth.*\|br-.*\|virbr.*\|tun.*\|tap.*\|wg.*\|tailscale.*\|CloudflareWARP)$` | 排除的介面（隧道/容器預設排除，VPN 不重複計算） |
| `displayMode` | `auto` | `auto` / `stacked`（雙行）/ `horizontal`（單行） |
| `autoStackMaxWidth` | 1920 | `auto` 模式下，螢幕寬度 ≤ 此值時改用雙行 |
| `stackedShowIcons` | `true` | 雙行時是否顯示方向箭頭；關閉改以顏色區分（下載 primary、上傳 tertiary） |

全部選項在設定 app 的 **Modules → Network Traffic** 頁有對應控件。

### 為什麼預設要雙行

ii 的 bar 右區是 `anchors { left: middleSection.right; right: parent.right }` 加
`layoutDirection: Qt.RightToLeft` 的 RowLayout。中間區用 `barCenterSideModuleWidth`
**固定**預留（`bar.verbose` 開啟時每側 360px），不隨螢幕縮放；右區內容一旦超出剩餘寬度，
就會往左溢出並蓋在 stock 元件上，而不是被裁切。

1920×1200、`bar.verbose: true`、10 個 workspace 的實測：

```
中間區 996px  →  右區可用 461px
右區需求 576px（指示器 153 + 托盤 110 + 本模塊 171 + 天氣 88 + 間距 42）
                                       溢出 115px
```

單行版 171px 是右區最寬的單一元件。雙行版約 58px，剛好把溢出補平。
寬螢幕不受這個限制，所以 `auto` 只在窄螢幕上壓縮。

字級不寫死，從 `baseBarHeight` 反推（膠囊高 = `baseBarHeight - 8`，行高 =
`floor((膠囊高 - 6) / 2)`，字級 = `clamp(行高 - 2, 9, small)`），因此改 bar 高度或
cornerStyle 時內容不會超出膠囊。

## 從舊手工補丁版遷移

若你先前手動安裝過（`services/NetworkTraffic.qml` ＋ BarContent/Config/BarConfig 補丁）：

1. 舊設定對照：`config.json` 的 `bar.networkTraffic.updateInterval` / `excludeRegex` → 搬到上表的模塊設定檔；`bar.networkTraffic.enable` → 由 `iimod enable/disable` 或設定 app 的 Modules 頁控制
2. 移除手工補丁（或等下次 dots 更新自然沖掉後 `iimod reapply`）再 `iimod install`
3. 手工版在 `config.json` 留下的 `bar.networkTraffic` 區塊會被 shell 的 JsonAdapter 自動剝掉，無需清理

## 實作說明（給模塊作者的參考）

- `TrafficLogic.qml`：輪詢邏輯**實例**（非單例——IIMP 模塊禁用 pragma Singleton），由 `bar.qml` 建立並向下傳遞
- `ConfigLoader.qml`：FileView＋JsonAdapter 寫自己的設定檔，永不碰 shell 的 `config.json`
- `bar.qml`：以 `BarGroup` 為根自帶藥丸外觀；固定欄寬防抖動（TextMetrics）；版面用「每個方向一個獨立 RowLayout」而非共用四格 GridLayout——GridLayout 會**跳過** `visible: false` 的項目而不是保留格位，箭頭一關兩行就會錯位
- `ConfigLoader.qml`：`onLoaded: writeAdapter()` 把合併後的設定寫回檔案。舊版寫的設定檔缺少後來新增的 key，JsonAdapter 對缺失的 key 是回傳型別零值而非 QML 宣告的預設值，不寫回就會讓升級的使用者拿到 `false` / `0`
- 每個用到的 stock API（BarGroup、StyledPopup、Graph、Network 服務）都在 manifest 宣告了探針
