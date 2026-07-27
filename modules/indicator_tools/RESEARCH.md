# 研究結論：原始補丁架構（2026-07-27）

朋友的右鍵選單已由本機運行態重新確認：

- Wi-Fi：NetworkManager Applet（`nm-applet --indicator`）
- 藍牙：Blueman Applet（`blueman-applet`）
- 兩者以 StatusNotifierItem／D-Bus Menu 提供內容；Wi-Fi 由橋接層呼叫 `SystemTrayItem.display()`，Blueman 則交給模塊自有 end4 面板呈現

本機套件與 SNI 證據：

| Applet | 套件 | `Id` | `Status` | Menu |
|---|---|---|---|---|
| NetworkManager Applet | `network-manager-applet 1.36.0-2` | `nm-applet` | Active | `/org/ayatana/NotificationItem/nm_applet/Menu` |
| Blueman | `blueman 2.4.6-2` | `blueman` | Active | `/org/blueman/sni/menu` |

因此 1.x／2.x 搜尋 iwgtk、Overskride、gnome-control-center 或自行解析 nmcli 的
方向全部封存。3.0.0 用 SNI 作唯一動作來源：stock Wi-Fi 圖示右鍵呼叫
`SystemTrayItem.display()`；Blueman D-Bus Menu 依 end4 模塊風格分組呈現；通用 tray
顯示模型隱藏兩個 applet 的重複 delegate。

舊資產的處理：

- `WifiPanel.qml`、`BtPanel.qml`、`NetworksLogic.qml`、`PanelShell.qml`、IPC 面板：刪除
- `splitNmcli` 等解析器：若未來需要多網卡診斷模塊，應另行遷移並補單元測試；
  不屬於 indicator_tools
- 四個 stock 指示器 anchor：沿用，但內容改為 SNI 選單橋

安全與生命週期：

- 模塊不 spawn applet；session 各啟動一次，避免熱重載重複程序
- 不處理 Wi-Fi 密碼、不呼叫 nmcli、不把 secret 放進 argv
- 托盤去重只比對 `nm-applet`、`blueman`，不使用 title 或 substring
