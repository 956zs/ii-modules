# indicator_tools — Applet 模塊面板（Tier B）

保留 stock bar 的 Wi-Fi／藍牙狀態圖示與左鍵側欄行為。右鍵兩個圖示會開啟
Material 風格的模組面板；面板直接渲染 `nm-applet`／`blueman-applet` 提供的
即時 D-Bus Menu，保留原生排序、disabled／check／radio 狀態、動作與遞迴子選單。
模組不建立第二套 NetworkManager 或 BlueZ 狀態機；兩個 applet 自帶的重複托盤
圖示會從 bar 顯示模型中精確隱藏。

| stock 圖示 | 右鍵 UI | 後端／StatusNotifier ID |
|---|---|---|
| Wi-Fi | Material 選單：保留 nm-applet 原生順序、狀態、網路、VPN 與子選單 | `nm-applet` |
| 藍牙 | Material 面板：控制、已連線裝置、快速操作、管理、更多；音訊 profile 以子頁呈現 | Blueman `blueman` |

水平／垂直、上／下／左／右 bar 都使用同一個橋。若 applet 尚未啟動，右鍵不
執行動作；stock 圖示與左鍵行為仍正常。

## 依賴與啟動

```bash
sudo pacman -S network-manager-applet blueman
```

模塊只消費 SNI 選單，**不管理 applet 行程生命週期**，避免模塊重載時重複
啟動。使用者 session 應各啟動一次：

```bash
nm-applet --indicator
blueman-applet
```

本機 Hyprland Lua 配置在 `custom/execs.lua` 的 `hyprland.start` handler 內以
`pgrep -x` 守衛後啟動；`blueman-applet` 會再產生 `blueman-tray` 輔助程序，
這是正常的一組 applet，不是重複實例。

本機驗證版本：`network-manager-applet 1.36.0-2`、`blueman 2.4.6-2`。運行時
實測兩者均為 `Status=Active` 且提供 D-Bus Menu：

- `nm-applet`：`/org/ayatana/NotificationItem/nm_applet/Menu`
- `blueman`：`/org/blueman/sni/menu`

## 安裝

```bash
iimod validate modules/indicator_tools/
iimod check modules/indicator_tools/
iimod install modules/indicator_tools/ --allow-patches
```

## 實作

- `AppletMenuBridge.qml` 直接從 `SystemTray.items.values` 以精確 `item.id` 找 applet，
  並把同一個 `item.menu` 分別交給 `WifiAppletMenu.qml` 與 `AppletMenu.qml`。
- Wi-Fi renderer 保留原始項目順序與動作，只壓縮首尾／連續 separator；空 label 依
  項目類型提供 fallback，未知新項目仍會顯示，check／radio 與遞迴子選單保持原樣。
- Blueman 根頁依穩定動作前綴分成控制、已連線裝置、快速操作、管理與更多；
  Disconnect／Audio Profiles 會依裝置名稱配對，主機音訊設定不再誤當連線裝置。
- Blueman 面板的動作使用一致的 Material Symbols；音訊 profile 子頁保留服務端
  選取狀態。每列使用 RippleButton 的 theme hover、快速色彩過渡與 ripple，
  不做造成布局位移的縮放動畫。
- 沒有命令輸出解析、密碼 argv 或第二套網路／藍牙狀態機。
- 四個圖示補丁（水平／垂直 × Wi-Fi／藍牙）用 path Loader 掛載橋接 MouseArea，
  只接收右鍵；stock 外層左鍵仍開側欄。
- `SysTray.qml` 的 pinned／unpinned 顯示陣列只排除精確 ID `nm-applet`、`blueman`；
  `TrayService` 和底層 `SystemTray.items` 保持完整，所以橋仍可取得選單。
- separator 改以過濾後陣列判斷，避免托盤只剩兩個被隱藏 applet 時留下孤立圓點。
- 3.0.0 是破壞性重寫：2.x 的自製 `WifiPanel`／`BtPanel`、nmcli parser、IPC 面板
  與舊翻譯已移除；3.3.0 完成兩個 applet 的 Material renderer 並修正 Blueman
  裝置配對與空 label 顯示；3.4.1 依 Quickshell 0.2.1 的 `LazyLoader.activeAsync`
  在 spare frame 建立 renderer，並在 menu/layout 尺寸穩定後才播放原本的 opacity 與
  elementResize 動畫。Popup window 幾何不再被 D-Bus model 更新逐幀改寫，renderer
  也不再反覆銷毀重建；anchor 使用 window-relative rect，避免綁住易失的 bar item。
  成熟 applet 仍是功能與 secret-agent 的唯一 owner。

卸載模塊後，stock 圖示不再接管 applet 選單，兩個 applet 的托盤圖示也會由
IIMP 重組自動恢復顯示；appet 行程本身由 session 啟動配置管理，不受模塊卸載影響。
