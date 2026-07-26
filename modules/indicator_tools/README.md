# indicator_tools — 右鍵指示器面板（Tier B）

右鍵 bar 上的 WiFi／藍牙指示圖示，開啟**模塊自製的 QML 面板**。
左鍵（開側欄）行為不變；四種 bar 位置（上/下/左/右）都適配。

| 面板 | 功能 | 後端 |
|---|---|---|
| 網路 | **多介面卡**：每張 WiFi 網卡各自成段（介面名＋目前連線/狀態＋該卡的掃描清單、逐卡連線/斷線/重掃）；藍牙網路共享（PAN/NAP）段列出 bluetooth 型連線設定檔＋bt 型裝置；乙太網路段（非 unavailable 時顯示）；全域 WiFi 開關、行內密碼、行內錯誤訊息 | **本模塊自行解析 `nmcli -t` 終端機輸出**（`NetworksLogic.qml`），不經 stock `Network` 服務——僅標題圖示沿用 `Network.materialSymbol` |
| 藍牙 | 裝置列表（已連/已配對/發現）、點擊連線/斷開、配對、移除、掃描、開關 | **Quickshell 原生 `Quickshell.Bluetooth`**（BlueZ D-Bus，零解析） |

## 緣起

還原並升級一個社群補丁：原補丁為了繞開 iwd 後端與 dots-hyprland nmcli
存儲不相通的問題，右鍵改開外部工具。本模塊進一步把 UI 收回 shell 內——
面板即 shell 元件，主題/字體/圓角全部原生一致。2.0.0→2.1.0 再進一步：
stock `Network` 服務只認得一張使用中的網卡，多網卡／藍牙網路共享的社群
使用情境需要看到**所有**網卡與可行的連線來源，因此網路面板改為自行對
nmcli 發號施令與解析結果。

## 安裝

```bash
iimod validate modules/indicator_tools/
iimod check    modules/indicator_tools/
iimod install  modules/indicator_tools/ --allow-patches   # Tier B
```

## 實作說明

- 四個 insert-only 補丁（水平/垂直 bar × WiFi/藍牙）：stock 圖示內插入只收
  右鍵的 `MouseArea`，`exec qs ipc call indicator_tools toggleWifi|toggleBt`
  ——補丁與模塊間以 IPC 解耦（stock 檔作用域碰不到模塊實例，這是協議下的
  正規通道；ModuleHost 的 reload 同款）
- `PanelShell.qml`：共用窗框——隨 bar 位置換錨、`HyprlandFocusGrab` 點外即關、
  Esc 關閉、密碼輸入時 `WlrKeyboardFocus.OnDemand`
- `NetworksLogic.qml`（非單例 Item 實例，`WifiPanel` 持有）：單一 `Process`
  依序換 `command` 跑完一輪 refresh——`radio wifi` 讀取狀態 → `device status`
  → `connection show`（取藍牙型設定檔）→ 逐張 WiFi 網卡各跑一次
  `dev wifi list ifname <dev>`；一個內部佇列保證任何時刻只有一個子行程在跑，
  永不無界生成。輸出全是 nmcli `-t` 終端機格式：以「未跳脫的冒號」切欄位，
  `\:`／`\\` 逐字反跳脫（欄位本身可能是含冒號的 MAC 或 SSID）；WiFi 掃描結果
  依 SSID 去重，同名 BSSID 保留使用中優先、其次訊號最強。`sections` 屬性
  每次 refresh 整批重建（WiFi／藍牙網路／乙太網路依序），`revision` 隨之遞增
  供需要顯式版本號的綁定使用
- WiFi 密碼流程改為面板自有的 `expandedSsid` 展開狀態＋
  `NetworksLogic.connectWifi(iface, ssid, password?)`，不再依賴 stock 的
  `askingPassword`／`changePassword()`
- 探針涵蓋所有非基線 API；`exec` capability 由補丁內容與 `NetworksLogic`
  的 nmcli 呼叫共同證實
