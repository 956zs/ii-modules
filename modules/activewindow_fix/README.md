# activewindow_fix - 視窗標題多螢幕修復

Tier B 相容性修復。stock `ActiveWindow.qml` 把 Hyprland monitor ID 當成
`HyprlandData.monitors` 的陣列索引；當 ID 與陣列位置不同時，bar 只顯示
`Workspace N`，無法顯示目前視窗標題。

## 行為

- 安裝後自動生效，沒有 UI 或設定。
- 以 `monitors.find(m => m.id === id)` 按 monitor ID 查找正確項目。
- 不需要系統依賴、不宣告 capabilities，也不儲存資料。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/activewindow_fix/
iimod check modules/activewindow_fix/
iimod install modules/activewindow_fix/ --allow-patches
```

## 相容性

| 項目 | 值 |
|---|---|
| Tested dots commit | `446504ad42` |
| Tested Quickshell | `0.2.1` |
| Patch target | `modules/ii/bar/ActiveWindow.qml` |
| Patch anchor | `HyprlandData.monitors[root.monitor?.id]` |

補丁錨點就是上游的錯誤表達式。上游修復後錨點會消失，後續 `check` 或 `reapply`
將把模塊標記為不相容，不會繼續套用過時修復。

## 實作說明

IIMP v1 沒有 replace 操作。模塊以 insert-only patch 插入 `Binding`，在執行期覆蓋
原本的 `biggestWindow` binding；沒有複製或取代 stock 檔案。

## 卸載

```bash
iimod uninstall activewindow_fix
```

IIMP 會從乾淨 stock 基底重組 QML 並移除補丁。若上游尚未修復，卸載後原始問題會
再次出現；若上游已修復，直接卸載即可完成退役。
