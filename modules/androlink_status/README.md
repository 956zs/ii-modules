# androlink_status - 手機狀態

Tier A bar 模組，在 bar 上用一個膠囊顯示 androlink 連結的手機：電量、充電、連線與背景助手
狀態、未讀通知數，點開有詳細資料和快捷動作。它只讀 androlink 寫的狀態檔，動作則以固定
參數執行 `androlink` 指令；手機電量偏低時，每次放電提醒一次。

> [!IMPORTANT]
> 需要支援狀態檔（`$XDG_RUNTIME_DIR/androlink/status.json`，version 1）與
> `--ring`、`--ring-stop`、`--send-clipboard`、`--dex`、`--webcam-stop` 的 androlink。
> 沒有狀態檔時，模組視為 androlink 未執行。

## 功能

| 狀態 | 膠囊 |
|---|---|
| 連線中 | 手機圖示、電量百分比；充電時加閃電、電量偏低時百分比變紅 |
| 未連線，或 androlink 超過 3 次心跳沒有更新狀態檔 | 同上但整個變淡 |
| 背景助手已停止 | 手機圖示右上角紅點 |
| 有未讀通知 | 百分比旁的數字徽章（可關） |
| 手機正在當攝影機 | 攝影機標記（隱私提示，不會變淡） |
| 手機正在響 | 圖示改用強調色並輕微搖動 |
| androlink 未執行 | 預設隱藏；可改成顯示變淡的圖示與「未執行」 |

點一下膠囊會在 bar 旁打開面板：

- 標題列：手機名稱與連線狀態（例如「透過區網連線」、「未連線」、「androlink 沒有回應」）。
- 攝影機使用中時，最上方有一列紅色提示和「停止」按鈕。
- 詳細資料：電量、連線方式（區網 / Tailscale / 其他）、背景助手、未讀通知。
- 動作：讓手機響（響鈴中變成停止響鈴）、傳送剪貼簿、開啟 DeX、打開 androlink。
- 有多支手機時，上方的晶片可切換要看哪一支；動作會帶上該手機的 id。
- 動作失敗時，下方顯示原因（androlink 未執行、找不到手機、逾時等）。

## 需求

| 項目 | 說明 |
|---|---|
| Tier | A，零 stock 修改 |
| 系統 | `androlink`（動作用，未安裝時面板會顯示無法執行）、`notify-send`（低電量提醒） |
| 相容性 | 以 Quickshell `0.3.2`、dots-hyprland `cb1c428bf8` 的 ii 測試；以 probe 檢查，不比對版本 |
| Capabilities | `exec`：執行 `androlink` 與 `notify-send` |

安裝時不檢查 `androlink` 是否存在，沒有它也能安裝。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/androlink_status/
iimod check modules/androlink_status/
iimod install modules/androlink_status/
```

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/androlink_status.json`；前四項也可在
**Settings > Modules > 手機狀態（androlink）** 調整。

| Key | 預設 | 說明 |
|---|---|---|
| `showWhenNotRunning` | `false` | androlink 未執行時保留變淡的膠囊，而不是隱藏 |
| `showUnread` | `true` | 顯示未讀通知數 |
| `lowBatteryReminder` | `true` | 開啟低電量提醒 |
| `lowBatteryThreshold` | `20` | 電量小於或等於這個百分比時提醒（1–95） |
| `rearmMargin` | `5` | 電量回升到門檻加這個值時重新啟用提醒（1–50） |
| `heartbeatSecs` | `30` | androlink 的心跳秒數；超過 3 倍沒更新即視為沒有回應（5–3600） |
| `pollSecs` | `10` | 狀態檔的備援重讀間隔（2–300） |
| `actionTimeoutSecs` | `15` | 面板動作超過這個秒數就停止並回報逾時（3–120） |

超出範圍的值會在讀取時修正為最近的合法值。狀態檔自己帶有 `heartbeat_s` 時以檔案為準。

## 資料與行為

- 狀態檔只含數字與狀態，不含通知內容、訊息或位址。模組不寫任何檔案，設定檔由
  ConfigLoader 維護。
- 解析規則：檔案不存在、不是合法 JSON、`version` 不是 1 以上的整數、或沒有 `updated`
  時，一律視為 androlink 未執行；`running` 不是 `true` 也一樣。手機欄位逐項檢查，
  不合約定的值改為未知。
- 動作一律用固定 argv，不經過 shell。只有在列出多支手機時才把手機 id 當成最後一個參數；
  id 超過 64 字元（CLI 的上限）、以 `-` 開頭或含控制字元時，不執行該手機的動作。
- 「打開 androlink」以 detached 方式執行，可能直接啟動 App；其他動作只轉送給執行中的
  androlink，結束代碼決定面板顯示的訊息。
- 低電量提醒在 window slot 只有一份，透過 `notify-send -a Shell` 送出；只有狀態為
  最新、手機已連線、未充電時才會觸發或重新啟用，狀態放在記憶體裡。

## 限制

- 重新載入 shell 會重置提醒狀態；電量已偏低時，重新載入後會再提醒一次。
- 面板固定在 bar 的右端（垂直 bar 時在側邊），和其他模組的面板相同，不會對齊膠囊位置。
- 垂直 bar 不顯示「未執行」文字與充電閃電。

## 實作說明

| 檔案 | 角色 |
|---|---|
| `bar.qml` | 膠囊與面板開關（每個螢幕各一份，只讀） |
| `main.qml` | window slot：設定檔擁有者與低電量提醒 |
| `PhoneStatus.qml` | 狀態檔讀取：檔案監看加備援重讀 |
| `StatusLogic.js` | 純函式：解析、膠囊顯示規則、動作 argv、結束代碼、提醒狀態機 |
| `PhonePanel.qml` | 面板內容與動作 |
| `CommandRunner.qml` | 一次執行一個動作，處理啟動失敗與逾時 |
| `PanelShell.qml` | `modules/aula_keys/PanelShell.qml` 的副本（只改 namespace 與寬度） |
| `settings.qml` | 設定頁片段 |
| `ConfigLoader.qml` | 母本 `lib/ConfigLoader.template.qml` 的副本，加上數值修正 |
| `tests/` | `StatusLogic.js` 的測試與 `status.json` 範例（缺檔以外的各種狀態） |

## 開發

```bash
node --test modules/androlink_status/tests/*.test.mjs
iimod validate modules/androlink_status/
iimod i18n check modules/androlink_status --locale zh_TW --locale zh_CN --deny-orphans
iimod check modules/androlink_status/
```
