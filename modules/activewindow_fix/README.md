# activewindow_fix — 視窗標題多螢幕修復（Tier B）

**修的是 stock bug**：`ActiveWindow.qml` 拿 Hyprland monitor ID 當
`HyprlandData.monitors` 的**陣列索引**。ID 恰好等於陣列位置時（單一內建螢幕
id 0）看不出問題；換到外接螢幕（id 變 1、陣列仍只有一個元素）後查找永遠
undefined，bar 左側從此只顯示「Workspace N」而不是視窗標題。

## 修法：insert-only 覆蓋綁定

協議沒有 replace 操作（設計如此），但 QML 的 `Binding{}` 可以在執行期
覆蓋既有綁定——插入一個 Binding 物件、以 `monitors.find(m => m.id === id)`
正確查找。

**自我退役**：補丁錨點就是那行壞碼。上游哪天修好、錨點消失，
`reapply` 會把本模塊標記 incompatible 並自動停用——bugfix 不會活得比 bug 久。

## 安裝

```bash
iimod install modules/activewindow_fix/ --allow-patches
```

建議同時到 end-4/dots-hyprland 回報上游（`monitors[id]` → `monitors.find(...)`）。
