# inline_reply - 通知直接回覆

Tier B 模組，讓 ii 的通知彈窗和側欄通知列表可以直接回覆訊息。它會在 stock
`NotificationServer` 開啟 inline reply（KDE 的通知擴充），並在 App 提供回覆功能的通知裡加上
一個回覆欄；androlink、KDE Connect 這類會送出 `inline-reply` action 的 App 都適用。

> [!IMPORTANT]
> 這是 Tier B 模組，會修改三個 stock QML 檔（見「實作說明」），安裝需要
> `--allow-patches`。dots-hyprland 更新後要執行 `iimod reapply` 重新套用。

## 互動

| 操作 | 結果 |
|---|---|
| 展開通知（展開按鈕或右鍵） | App 提供回覆時，內文下方出現回覆欄 |
| 點回覆欄 | 開始輸入；在彈窗裡會暫時接管鍵盤 |
| Enter 或送出按鈕 | 送出回覆；空白內容不會送出 |
| Esc | 清空回覆欄並交還鍵盤 |
| 點彈窗外面 | 交還鍵盤，回覆欄保留已輸入的文字 |

- 回覆欄的提示文字用 App 提供的標籤（例如「Reply to Amy」），沒有時顯示「回覆…」。
- 送出後，一般通知會由 Quickshell 關閉；常駐通知（`resident`）會留著，送出按鈕短暫顯示
  勾號。
- 彈窗在回覆欄正在輸入或還有文字時不會自動消失；交還後回到 stock 行為（指標不在通知
  上就立刻收起）。
- 側欄通知列表本來就能接收鍵盤，回覆欄直接可用，Esc 只會清空回覆欄，不會關閉側欄。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | B，修改 `services/Notifications.qml`、`modules/common/widgets/NotificationItem.qml`、`modules/ii/notificationPopup/NotificationPopup.qml` |
| Quickshell | 需要 `NotificationServer.inlineReplySupported` 與 `Notification.sendInlineReply()`（0.2.0 起提供；以 0.3.2 測試） |
| 合成器 | Hyprland（彈窗輸入時用 `HyprlandFocusGrab` 接管與交還鍵盤） |
| 系統相依 | 無 |
| Capabilities | 無 |

相容性用 probe 檢查錨點所在的 stock 結構，不比對版本；任何錨點或 probe 失敗時
`iimod check` 會拒絕安裝，`iimod reapply` 會停用此模組而不會改壞 shell。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/inline_reply/
iimod check modules/inline_reply/
iimod install modules/inline_reply/ --allow-patches
```

安裝後重新載入 shell。正在執行的 App 若在啟動時就快取了通知伺服器的能力清單
（androlink 會），要重新啟動該 App 才會開始送出 `inline-reply` action。

## 設定

沒有設定。停用模組（`iimod disable inline_reply`）會移除所有補丁，通知伺服器回到不宣告
inline reply 的 stock 狀態。

## 資料與行為

- 回覆內容只經過 session D-Bus 的 `NotificationReplied` 訊號送給 App，模組不寫檔、
  不寫任何 log。
- 只有 Quickshell 的 live `Notification` 物件還在、而且 `hasInlineReply` 為 true 時才
  顯示回覆欄。ii 從檔案還原的舊通知、或 App 已經關掉的通知，都不會出現回覆欄。
- 開啟 inline reply 後，Quickshell 會把 `inline-reply` action 從一般 action 按鈕列表移除，
  改由回覆欄處理。

## 限制

- 只支援 ii 面板家族；waffle 家族的通知元件沒有回覆欄。
- 收合的通知不會顯示回覆欄，要先展開；這和 stock action 按鈕的行為一致。
- 在彈窗輸入時打開右側欄或媒體控制，stock 會收起所有彈窗，未送出的文字會一起消失。
- 正在輸入時，Hyprland 的全域快捷鍵照常生效。

## 實作說明

| 檔案 | 角色 |
|---|---|
| `ReplyField.qml` | 回覆欄與送出按鈕，管理輸入、保留彈窗與鍵盤交接 |
| `ReplyLogic.js` | 純函式：能否回覆、提示文字、送出內容、所在通知群組、交還後是否收起 |
| `main.qml` | 空的 window slot（IIMP 至少要一個 slot） |
| `tests/inline-reply.test.mjs` | 純函式與補丁契約測試 |

| 補丁 | 目標 | 作用 |
|---|---|---|
| 0 | `Notifications.qml` 的 `NotificationServer` | `inlineReplySupported: true` |
| 1 | `Notifications.qml` 的 `Notif` 包裝物件 | `iimpReplyHold`：這個彈窗正在使用回覆欄 |
| 2 | `Notifications.qml` 的 `timeoutNotification()` | `iimpReplyHold` 時不收起彈窗 |
| 3 | `Notifications.qml` 的 service 屬性區 | `iimpReplyComposer`：正在彈窗輸入的通知 id（-1 為無） |
| 4 | `NotificationItem.qml` 的 import 區 | `import qs.mod.inline_reply as InlineReply` |
| 5 | `NotificationItem.qml` 的 action 列之前 | 插入 `InlineReply.ReplyField` |
| 6 | `NotificationPopup.qml` 的 `PanelWindow` | 有人輸入時 `keyboardFocus: OnDemand` 與 `HyprlandFocusGrab`，點外面清除 |

回覆欄用 `ReplyLogic.hostGroup()` 往上找 stock `NotificationGroup`，以它的 `popup`
屬性區分彈窗與側欄；只有彈窗裡的回覆欄會設定 `iimpReplyHold` 與
`iimpReplyComposer`。

## 開發

```bash
node --test modules/inline_reply/tests/*.test.mjs
iimod validate modules/inline_reply/
iimod i18n check modules/inline_reply --locale zh_TW --locale zh_CN --deny-orphans
iimod check modules/inline_reply/
```
