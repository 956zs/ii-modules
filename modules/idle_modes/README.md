# idle_modes - 三段閒置模式

Tier B 模塊，把側欄「Keep awake」磁貼改成三段式閒置模式，並在重開機或 shell
重啟後還原上次選的模式。它 patch stock `Idle` service 與磁貼 model；休眠的部分
由 shell 目錄外的一支 hypridle gate script 把關。

> [!IMPORTANT]
> 休眠閘門設定在 `~/.config/hypr/hypridle.conf`，dots-hyprland 更新會覆寫這個檔案。
> 每次 dots 更新後都要重新套用 `$suspend_cmd` 那一行和 gate 的 `on-resume` 那一行
>（見安裝），否則半開模式又會休眠。

## 互動

點磁貼依序切換模式：

| 模式 | 磁貼 | 鎖屏（5 分鐘） | 關螢幕（10 分鐘） | 休眠（15 分鐘） |
| --- | --- | --- | --- | --- |
| off | `coffee`，不高亮，「全關（會休眠）」 | 會 | 會 | 會 |
| half | `bedtime_off`，高亮，「半開（只關螢幕）」 | 會 | 會 | 不會 |
| full | `coffee`，高亮，「全開（常亮）」 | 不會 | 不會 | 不會 |

從鎖屏畫面以「解鎖後保持喚醒」的方式解鎖時會切到 full。電量過低時的自動休眠不受
任何模式影響。

### androlink 使用中不休眠

off 模式下，androlink 正在做休眠會打斷的事時，gate 也會跳過這次閒置休眠：手機的
麥克風或攝影機正串流到這台電腦，或檔案正在傳輸。鎖屏和關螢幕照常進行。

| androlink 狀態檔 | 電源 | 閒置休眠 |
| --- | --- | --- |
| 最新，`keep_awake` 有原因 | 插著電，或沒有電池 | 跳過 |
| 最新，`keep_awake` 有原因 | 電量不低於 `keepAwakeBatteryFloor` | 跳過 |
| 最新，`keep_awake` 有原因 | 電量低於下限，或讀不到電量 | 照常 |
| 最新但 `keep_awake` 是空的、過期、已結束、不存在或無效 | 不限 | 照常 |

擋下休眠不是一次就定案。電腦持續閒置時，gate 每 `keepAwakeRecheckSecs` 秒重新檢查
一次，只要符合上表「照常」的情況就立刻休眠，例如電量掉到下限以下或狀態檔過期。擋滿
`keepAwakeMaxHoldMins` 分鐘後，不論 androlink 回報什麼都會休眠。

`keep_awake` 變空時會先給一段寬限期，因為串流重新連線時 androlink 會暫時拿掉
`mic` 和 `webcam`。要在 `keepAwakeReleaseGraceSecs` 秒內每次檢查都是空的才會
休眠；原因回來就繼續擋下。只有在電源條件允許擋下休眠時才有寬限期。

有輸入時（hypridle 執行 gate 的 `resume`）、模式切到半開或全開、有螢幕重新亮起，或
等待期間電腦睡過（闔上螢幕、選單的「睡眠」）時，gate 會結束等待，不會休眠。

闔上螢幕、ii 選單的「睡眠」和低電量自動休眠都不經過 gate，行為不變。

## 需求

| 依賴 | 用途 |
| --- | --- |
| hypridle | 閒置計時；休眠監聽會呼叫 gate script，它的 `on-resume` 會停止等待中的 gate |
| jq | gate script 讀取模式、選項與 androlink 的狀態檔 |
| hyprctl、flock | 擋下休眠期間，gate 確認螢幕仍然關閉，並保證只有一份在等待 |
| androlink（選用） | 寫入帶 `keep_awake` 的 `$XDG_RUNTIME_DIR/androlink/status.json`；沒有它時 gate 只看模式 |
| Android 風格快捷面板 | 磁貼 model patch；classic 風格按鈕仍會切換，但只有 full 會高亮 |

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/idle_modes
iimod check modules/idle_modes
iimod install modules/idle_modes --allow-patches
```

安裝 gate script 並讓 hypridle 指向它（裝一次即可；`hypridle.conf` 的兩處修改在每次
dots-hyprland 更新後要重新套用）：

```bash
install -Dm755 modules/idle_modes/idle-mode-gate.sh ~/.config/hypr/custom/scripts/idle-mode-gate.sh
sed -i 's|^\$suspend_cmd = .*|$suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend|' ~/.config/hypr/hypridle.conf
grep -q 'idle-mode-gate.sh resume' ~/.config/hypr/hypridle.conf ||
    sed -i 's|^\([[:space:]]*\)on-timeout = \$suspend_cmd[[:space:]]*$|&\n\1on-resume = ~/.config/hypr/custom/scripts/idle-mode-gate.sh resume|' ~/.config/hypr/hypridle.conf
pkill -x hypridle; hyprctl dispatch 'hl.dsp.exec_cmd("hypridle")'
```

第二個 `sed` 會在休眠監聽加上一行，讓輸入能停止等待中的 gate：

```ini
listener {
    timeout = 900 # 15mins
    on-timeout = $suspend_cmd
    on-resume = ~/.config/hypr/custom/scripts/idle-mode-gate.sh resume
}
```

如果那個監聽已經有 `on-resume`，不要再加第二行：請手動把 gate 的 `resume` 呼叫
加進現有的指令。

請照上面的方式透過 Hyprland 重啟 hypridle，避免它跑在終端機的 process group 裡。

裝好的 gate script 是複本：更新模塊後要再執行一次上面的 `install` 那一行，hypridle
才會用到新版。

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/idle_modes.json`。

| Key | 預設 | 說明 |
| --- | --- | --- |
| `mode` | `"off"` | `"off"`、`"half"` 或 `"full"`；無效值會修正為 `"off"` |
| `keepAwakeBatteryFloor` | `20` | 電量（百分比）不低於這個值時，androlink 的使用中原因才會擋下閒置休眠（0–100） |
| `keepAwakeMaxAgeSecs` | `90` | androlink 的狀態檔要在這麼多秒內寫過才算數；檔案寫明的 `heartbeat_s` 三倍較長時以它為準（15–3600） |
| `keepAwakeRecheckSecs` | `60` | 擋下閒置休眠期間，每隔這麼多秒重新檢查一次（15–600） |
| `keepAwakeMaxHoldMins` | `120` | 每段閒置最多擋下閒置休眠這麼多分鐘，之後就休眠（1–1440） |
| `keepAwakeReleaseGraceSecs` | `45` | 擋下期間，`keep_awake` 要空滿這麼多秒才休眠，避免串流重新連線時通話被中斷（15–600） |

磁貼每次切換都會寫入這個檔案，手動修改也會即時套用。超出範圍的數值會由 shell 修正為
最近的合法值；gate script 每次執行都會讀取這個檔案，並用同樣的範圍修正。

## 資料與行為

- Window entry 在 shell 啟動時讀取模式並呼叫 `Idle.setIdleMode`，同時同步 stock
  `Persistent.states.idle.inhibit` 旗標。
- full 使用 stock Wayland idle inhibitor，hypridle 不會偵測到閒置。完整重啟 shell
  後，inhibitor 會在 surface 顯示約 3 秒後重建，因為 Hyprland 不會套用 surface
  map 之前就建立的 inhibitor（見實作說明）。
- half 與 off 讓 hypridle 照常運作；只有檔案寫 `"off"` 時 gate script 才會休眠
  （檔案缺少、無法讀取或值無效時也視為 `"off"`）。
- gate 只在 `XDG_RUNTIME_DIR` 是絕對路徑、檔案不超過 64 KiB 時讀取
  `$XDG_RUNTIME_DIR/androlink/status.json`。檔案必須是單一 JSON 物件，`version` 為
  1、`running` 為 true，`updated` 不早於新鮮度上限（也不超前它的三分之一）。
  `keep_awake` 缺少或為 `null` 時視為沒有原因。
- 新鮮度上限是 `keepAwakeMaxAgeSecs`。狀態檔最上層的 `heartbeat_s` 介於 1 到 3600
  時，若三次 heartbeat 較長就改用它；其他值一律忽略。
- 原因代碼只記錄符合代碼格式的項目（小寫字母、數字與 `_`，最多 32 字元；最多 8 個，
  排序並去除重複），清單裡的其他內容一律忽略。
- 電源資訊來自 `/sys/class/power_supply`：任何 `online` 為 1 的 `Mains` 視為插電；
  電量是系統電池 `capacity` 的平均值。周邊裝置電池（`scope` 為 `Device`）與 USB-C
  對端電源不列入。沒有 `type` 的項目，名稱是 `AC*`、`ADP*` 或 `ACAD*` 時視為電源
  供應器，`BAT*` 視為電池。
- 「沒有電池」（桌機，比照插電擋下休眠）的條件是 power supply 目錄讀得到，而且裡面
  既沒有系統電池也沒有 `Mains`。目錄讀不到、電池讀不到電量，或 `Mains` 離線且看
  不到電池時，都視為電量不明，照常休眠。
- 擋下休眠時，gate 會在背景等待。它的 PID 寫在 `$XDG_RUNTIME_DIR/idle-mode-gate.pid`
  （權限 0600，以 `flock` 鎖住）；只有 `XDG_RUNTIME_DIR` 是使用者自己、其他人無法
  寫入的目錄時才會等待。`idle-mode-gate.sh resume` 只會停止持有那把鎖、正在執行
  gate `suspend` 的程序；沒人鎖住的殘留檔案會被刪除。新的一段閒置會取代仍在等待
  的 gate。
- 每次檢查都會重新讀取模式、電量下限與新鮮度選項、狀態檔與電源；檢查間隔、擋下
  上限與寬限期在開始等待時讀取。等待會縮短到剛好在擋下上限或寬限期結束時檢查，
  兩者都不會超過。
- 檢查後要休眠前，所有螢幕都必須仍然關閉（`hyprctl monitors` 回報 `dpmsStatus`
  為 false）。有螢幕亮著或沒有回應時，結束等待且不休眠。
- 等待期間電腦睡過時，結束等待且不休眠，因為喚醒後螢幕可能要到第一次輸入才會
  亮。`/sys/power/suspend_stats/success` 多算了一次休眠，或 `/proc/uptime` 的開機
  時鐘（睡眠時照樣走）比等待時間多走超過 15 秒，就視為睡過。讀不到
  `/proc/uptime` 時改用系統時鐘。
- 每次執行印出一行判斷結果與原因，例如
  `idle-mode-gate: mode off, androlink keep_awake mic, on AC, not suspending,
  checking again every 60 s for up to 120 min`；等待結束時再印一行，例如
  `idle-mode-gate: mode off, androlink keep_awake none for 45 s, suspending`。
- `idle-mode-gate.sh suspend --dry-run` 只印出判斷結果，不會休眠也不會等待。

## 限制

- classic 風格快捷按鈕沒有 patch：會切換模式，但只有 full 會顯示高亮。
- 調整鎖屏或關螢幕時間仍需編輯 `hypridle.conf`。
- 重新檢查需要螢幕在休眠監聽觸發前就已關閉，也就是 stock 的時間安排（10 分鐘關
  螢幕、15 分鐘休眠）。休眠監聽之前沒有關螢幕的監聽，或沒有 `hyprctl` 時，第一次
  檢查就會結束等待且不休眠，要等有輸入、再閒置滿一段時間才會休眠。
- 沒有 `on-resume` 那一行時，只能在下次檢查看到螢幕亮起才知道有輸入。請加上那一行。
- 擋滿 `keepAwakeMaxHoldMins` 時，即使插著電、正在通話或傳檔也會休眠。無人看管的
  長時間傳檔請調高上限。
- 閒置期間通話或傳檔結束後，要再過 `keepAwakeReleaseGraceSecs` 秒才會休眠。重新
  連線超過寬限期時，仍會結束擋下。
- 每段閒置的第一次檢查（休眠監聽觸發時）沒有寬限期：那時 `keep_awake` 是空的就
  直接休眠。
- 等待期間電腦睡過後，這段閒置不會再閒置休眠：要等有輸入、再閒置滿一段時間才會
  休眠。
- 只以 USB 電源出現（沒有 `Mains` 項目）的充電器不會被當成插電，改由電量下限決定。
- shell 啟動完成前 full 不會生效：window 模塊可能要數十秒才載入完成，之後還有
  3 秒的重建延遲。

## 實作說明

Patches（insert-only）：`services/Idle.qml` 加入 `idleMode`、`idleModesActive`、
`setIdleMode()` 與 `cycleIdleMode()`，模塊啟用時 `toggleInhibit()` 改走模式切換。
`IdleInhibitorToggle.qml` 加上 id 與四個 `Binding`（`toggled`、`icon`、
`statusText`、`tooltipText`），都以 `Idle.idleModesActive` 為條件，entry 沒載入時
會回到 stock 外觀。

`Idle.qml` 的第三個 patch 處理 inhibitor 的生命週期。Hyprland 0.56 只在 inhibitor
建立時，以及焦點、視窗或全螢幕事件時檢查其 surface 是否可見，layer surface map
時不會重新檢查。shell 啟動時，還原的 inhibit 旗標會在 0x0 `PanelWindow` map 之前
就啟用 stock inhibitor，因此它在下次焦點變化前都不會生效，hypridle 照樣鎖屏與休眠。

修正方式是由 `backingWindowVisibleChanged` 啟動一次性 timer，3 秒後把 `enabled`
關掉再打開。切換 `enabled` 會重新發出 `windowChanged`，所以 timer 不能透過
`idleInhibitor.window` 綁定 `running`，否則會無限重啟。

## 開發

```bash
node --test modules/idle_modes/tests/*.test.mjs
bash modules/idle_modes/idle-mode-gate.sh suspend --dry-run
bash modules/idle_modes/idle-mode-gate.sh resume
iimod validate modules/idle_modes
iimod check modules/idle_modes
```

`tools/idle-inhibit-probe/probe.sh` 會詢問 compositor 目前是否有 idle inhibitor
生效，輸出 `INHIBITED`、`NOT_INHIBITED` 或 `INCONCLUSIVE`（8 秒偵測期間有輸入）。
要驗證重啟路徑：把 `mode` 設為 `"full"`，用 `qs -c ii kill` 停掉 shell 並從
Hyprland 重新啟動 `qs -c ii`，等 window 模塊載入完成後再執行 probe。
