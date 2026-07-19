# network-traffic — IIMP 參考模塊

Bar 上下行流量計（Tier A，零 stock 補丁）。即時速率、開機累計、hover 彈窗含 60 樣本趨勢曲線。

## 安裝

```bash
iimod validate network-traffic/
iimod check network-traffic/
iimod install network-traffic/     # 或先 iimod pack 再裝 .iimod
```

## 設定

`~/.config/illogical-impulse/modules/network-traffic.json`：

| Key | 預設 | 說明 |
|---|---|---|
| `updateInterval` | 2000 | 輪詢間隔（毫秒） |
| `excludeRegex` | `^(lo\|docker.*\|veth.*\|br-.*\|virbr.*\|tun.*\|tap.*\|wg.*\|tailscale.*\|CloudflareWARP)$` | 排除的介面（隧道/容器預設排除，VPN 不重複計算） |

## 從舊手工補丁版遷移

若你先前手動安裝過（`services/NetworkTraffic.qml` ＋ BarContent/Config/BarConfig 補丁）：

1. 舊設定對照：`config.json` 的 `bar.networkTraffic.updateInterval` / `excludeRegex` → 搬到上表的模塊設定檔；`bar.networkTraffic.enable` → 由 `iimod enable/disable` 或設定 app 的 Modules 頁控制
2. 移除手工補丁（或等下次 dots 更新自然沖掉後 `iimod reapply`）再 `iimod install`
3. 手工版在 `config.json` 留下的 `bar.networkTraffic` 區塊會被 shell 的 JsonAdapter 自動剝掉，無需清理

## 實作說明（給模塊作者的參考）

- `TrafficLogic.qml`：輪詢邏輯**實例**（非單例——IIMP 模塊禁用 pragma Singleton），由 `bar.qml` 建立並向下傳遞
- `ConfigLoader.qml`：FileView＋JsonAdapter 寫自己的設定檔，永不碰 shell 的 `config.json`
- `bar.qml`：以 `BarGroup` 為根自帶藥丸外觀；固定欄寬防抖動（TextMetrics）
- 每個用到的 stock API（BarGroup、StyledPopup、Graph、Network 服務）都在 manifest 宣告了探針
