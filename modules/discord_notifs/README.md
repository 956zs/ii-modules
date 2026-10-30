# discord_notifs - Discord 近期通知面板

Tier A window 模組，用浮動面板列出近期的 Discord 通知，分「全部、私訊、伺服器、其他」
四個分頁。資料直接取自 shell 自己的通知服務（即時通知加上已保存的歷史），模組不連線到
Discord，也不讀 Discord 的任何資料。

## 使用

面板沒有 bar 按鈕，靠 IPC 開關，可以綁熱鍵或繪圖板按鈕：

```bash
qs -c ii ipc --any-display call discordnotifs toggle
qs -c ii ipc --any-display call discordnotifs cycle
qs -c ii ipc --any-display call discordnotifs setFilter dm
```

| 函式 | 作用 |
|---|---|
| `toggle` | 開或關面板 |
| `open` / `close` | 明確開或關 |
| `cycle` | 切到下一個分頁（全部 → 私訊 → 伺服器 → 其他），並開啟面板 |
| `setFilter <all\|dm\|server\|other>` | 直接切到指定分頁並開啟面板，名稱不合法時忽略 |

面板開著時，點面板外或按 Esc 關閉；分頁按鈕旁的數字是該分類的通知數。

> [!NOTE]
> 函式名不能叫 `show`：`qs ipc call` 會把它當成別的子命令，只印出說明而不執行。

## 分類規則

Discord 桌面版的通知只有標題與內文，沒有正式的類型欄位，所以分類靠標題格式判斷：

| 分頁 | 判斷依據 |
|---|---|
| 伺服器 | 標題最後的括號內含 `#`，例如 `Alice (#general, My Server)` |
| 私訊 | 標題只有名稱，沒有含 `#` 的括號 |
| 其他 | 標題含 Quest、Nitro、Orbs，或標題是空的 |

伺服器通知的括號以最後一個 `, ` 切出頻道與伺服器名稱；論壇貼文的括號內含 `貼文標題 in #頻道`，
整段都會顯示在頻道欄。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | A，零 stock 修改 |
| 系統 | Discord 桌面版（或 Vesktop、Equicord 等）要透過 libnotify 送桌面通知 |
| 相容性 | dots-hyprland `446504ad42`、Quickshell `0.2.1` 測試通過 |
| Capabilities | 無 |

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/discord_notifs.json`。

| Key | 預設 | 說明 |
|---|---|---|
| `filter` | `"all"` | 目前分頁，切換分頁時自動寫入 |
| `maxItems` | `30` | 每個分頁最多列出幾則 |
| `appNames` | `["discord","vesktop","equicord","vencord","legcord","armcord"]` | 視為 Discord 的通知來源名稱（JSON 陣列字串，不分大小寫） |
| `panelWidth` | `420` | 面板寬度，單位 px |

## 限制

- 頭像來自通知本身的圖片，shell 重啟後已保存的舊通知取不到圖，改顯示分類圖示。
- 無法區分「被提及」與一般伺服器訊息，Discord 通知沒有這個資訊。
- 只列出 shell 通知歷史裡有的通知；通知被清除，或當時開了勿擾模式而 Discord 沒送出，就看不到。

## 測試

```bash
node --test modules/discord_notifs/tests/logic.test.mjs
```
