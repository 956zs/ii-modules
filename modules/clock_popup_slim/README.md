# clock_popup_slim — 精簡時鐘彈窗（Tier B）

把 bar 時鐘的 hover 彈窗縮成一行日期：隱藏「System uptime」列和「To Do」區塊。

## 安裝

```bash
iimod validate modules/clock_popup_slim/
iimod check    modules/clock_popup_slim/
iimod install  modules/clock_popup_slim/ --allow-patches   # Tier B 需明確同意
```

要回到完整彈窗：`iimod disable clock_popup_slim`（重組引擎會從乾淨基底還原 stock 檔）。

## 實作說明

兩個 insert-only 補丁，都對 `modules/ii/bar/ClockWidgetPopup.qml`：

| # | 錨點 | 插入 | 效果 |
|---|---|---|---|
| 0 | `label: Translation.tr("System uptime:")` | `visible: false` | 隱藏 uptime 列 |
| 1 | `Layout.fillWidth: true` | `visible: false` | 隱藏整個 To Do `Column` |

- 隱藏而非刪除：SPEC 1.0 的補丁只有 insert-after / insert-before（§12 教訓 4——
  不留上游程式碼的陳舊快照）。`ColumnLayout` 會跳過 invisible 子項，佈局自動收縮。
- 錨點是 stock 檔中的唯一單行；上游改寫導致錨點消失或重複時，安裝/`reapply`
  會**大聲失敗**（exit 8）而不是裝出半套。
- 橫向與縱向 bar 共用同一個彈窗檔，一組補丁同時生效。
- 無 QML payload、無 capabilities、無使用者可見字串（不需翻譯檔）。
