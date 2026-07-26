# indicator_tools — 右鍵指示器面板（Tier B）

右鍵 bar 上的 WiFi／藍牙指示圖示，開啟**模塊自製的 QML 面板**。
左鍵（開側欄）行為不變；四種 bar 位置（上/下/左/右）都適配。

| 面板 | 功能 | 後端 |
|---|---|---|
| Wi-Fi | 網路列表（訊號/加密/使用中）、點擊連線、行內密碼、重掃、開關 | stock `Network` 服務（nmcli 由 stock 封裝，零解析） |
| 藍牙 | 裝置列表（已連/已配對/發現）、點擊連線/斷開、配對、移除、掃描、開關 | **Quickshell 原生 `Quickshell.Bluetooth`**（BlueZ D-Bus，零解析） |

## 緣起

還原並升級一個社群補丁：原補丁為了繞開 iwd 後端與 dots-hyprland nmcli
存儲不相通的問題，右鍵改開外部工具。本模塊進一步把 UI 收回 shell 內——
面板即 shell 元件，主題/字體/圓角全部原生一致。

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
- WiFi 密碼流程直接復用 stock 的 `askingPassword` 狀態機＋`changePassword()`
- 探針涵蓋所有非基線 API；`exec` capability 由補丁內容的 lint 掃描證實
