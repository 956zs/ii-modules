# indicator_tools - 指示器 Applet 選單

Tier B 模塊，為 stock Wi-Fi 與藍牙圖示提供 Material 選單。模塊直接渲染
`nm-applet` 與 `blueman-applet` 的 D-Bus Menu，不建立第二套 NetworkManager
或 BlueZ 狀態機。

stock 圖示與左鍵開側欄的行為保持不變。兩個 applet 的重複托盤圖示會從 bar
顯示模型隱藏，但底層 StatusNotifier item 仍保留供模塊使用。

## 使用方式

| stock 圖示 | 左鍵 | 右鍵 |
|---|---|---|
| Wi-Fi | 開啟 stock 側欄 | 顯示 nm-applet 網路、VPN 與子選單 |
| 藍牙 | 開啟 stock 側欄 | 顯示 Blueman 裝置、操作、管理與 audio profiles |

選單保留 applet 原生排序、disabled、check、radio、動作與遞迴子選單。水平、
垂直與四種 bar 位置共用同一組 bridge；同一時間只會開啟一個選單。

## 需求

`module.json` 要求以下 binaries：

```bash
sudo pacman -S network-manager-applet blueman
```

模塊只消費 applet 發布的 StatusNotifier/D-Bus Menu，不管理 process lifecycle。
請由桌面 session、Hyprland autostart 或 user service 各啟動一次：

```bash
nm-applet --indicator
blueman-applet
```

模塊宣告 `dbus` capability，沒有使用者設定檔。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/indicator_tools/
iimod check modules/indicator_tools/
iimod install modules/indicator_tools/ --allow-patches
```

## 相容性與限制

| 項目 | 值 |
|---|---|
| Tested dots commit | `446504ad42` |
| Tested Quickshell | `0.2.1` |
| Tier | B，stock bar 與 tray insert-only patches |
| Applet IDs | `nm-applet`、`blueman` |

- 若 applet 尚未啟動或沒有發布 D-Bus Menu，右鍵不執行動作；stock 左鍵仍正常。
- 已知 Wi-Fi/Blueman actions 優先使用 Material Symbols；未知 applet icon 才使用
  native icon fallback。
- 模塊依賴目前 stock `RippleButton`、SystemTray models 與 menu contracts；錨點或
  probes 失效時，`iimod check` 會拒絕安裝。

## 疑難排解

| 症狀 | 檢查 |
|---|---|
| 右鍵沒有反應 | 確認對應 applet process 正在執行 |
| 選單不存在 | 確認 applet 已發布 StatusNotifier item 與 D-Bus Menu |
| 同一 applet 出現多份 | 檢查 session autostart 是否重複啟動 process |
| 安裝後 probe 失敗 | 更新模塊或使用相符的 dots/Quickshell 版本 |

## 實作說明

| 元件 | 職責 |
|---|---|
| `AppletMenuBridge.qml` | 依精確 item ID 取得 applet menu，協調 popup 與 focus lifecycle |
| `WifiAppletMenu.qml` | 依 nm-applet 原始順序渲染網路與 VPN menu |
| `AppletMenu.qml` | 渲染 Blueman 分組、裝置操作與 profile 子頁 |
| bar patches | 把右鍵 `altAction` 分派給命中的 Wi-Fi/Bluetooth bridge |
| `SysTray.qml` patches | 只從可見模型排除精確 applet IDs，保留底層 items |

stock `RippleButton` 是唯一 pointer owner。Renderer 透過 `LazyLoader.activeAsync`
建立，popup 在 layout 尺寸穩定後才播放既有動畫；真實 popup window handle 會加入
focus grab，讓內部 action、同圖示 toggle 與點外關閉能共存。

## 卸載

```bash
iimod uninstall indicator_tools
```

IIMP 重組後，stock 圖示不再開啟 applet 選單，`nm-applet` 與 `blueman` 托盤圖示會
恢復顯示。Applet processes 仍由使用者的 session 啟動配置管理，不會因卸載而停止。
