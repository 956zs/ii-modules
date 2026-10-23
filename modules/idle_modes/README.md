# idle_modes - 三段閒置模式

Tier B 模塊，把側欄「Keep awake」磁貼改成三段式閒置模式，並在重開機或 shell
重啟後還原上次選的模式。它 patch stock `Idle` service 與磁貼 model；休眠的部分
由 shell 目錄外的一支 hypridle gate script 把關。

> [!IMPORTANT]
> 休眠閘門設定在 `~/.config/hypr/hypridle.conf`，dots-hyprland 更新會覆寫這個檔案。
> 每次 dots 更新後都要重新套用那一行 `$suspend_cmd`（見安裝），否則半開模式又會
> 休眠。

## 互動

點磁貼依序切換模式：

| 模式 | 磁貼 | 鎖屏（5 分鐘） | 關螢幕（10 分鐘） | 休眠（15 分鐘） |
| --- | --- | --- | --- | --- |
| off | `coffee`，不高亮，「全關（會休眠）」 | 會 | 會 | 會 |
| half | `bedtime_off`，高亮，「半開（只關螢幕）」 | 會 | 會 | 不會 |
| full | `coffee`，高亮，「全開（常亮）」 | 不會 | 不會 | 不會 |

從鎖屏畫面以「解鎖後保持喚醒」的方式解鎖時會切到 full。電量過低時的自動休眠不受
任何模式影響。

## 需求

| 依賴 | 用途 |
| --- | --- |
| hypridle | 閒置計時；休眠監聽會呼叫 gate script |
| jq | gate script 從模塊設定讀取模式 |
| Android 風格快捷面板 | 磁貼 model patch；classic 風格按鈕仍會切換，但只有 full 會高亮 |

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/idle_modes
iimod check modules/idle_modes
iimod install modules/idle_modes --allow-patches
```

安裝 gate script 並讓 hypridle 指向它（裝一次即可；`hypridle.conf` 那一行在每次
dots-hyprland 更新後要重新套用）：

```bash
install -Dm755 modules/idle_modes/idle-mode-gate.sh ~/.config/hypr/custom/scripts/idle-mode-gate.sh
sed -i 's|^\$suspend_cmd = .*|$suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend|' ~/.config/hypr/hypridle.conf
pkill -x hypridle; hyprctl dispatch 'hl.dsp.exec_cmd("hypridle")'
```

請照上面的方式透過 Hyprland 重啟 hypridle，避免它跑在終端機的 process group 裡。

## 設定

設定檔位於 `~/.config/illogical-impulse/modules/idle_modes.json`。

| Key | 預設 | 說明 |
| --- | --- | --- |
| `mode` | `"off"` | `"off"`、`"half"` 或 `"full"`；無效值會修正為 `"off"` |

磁貼每次切換都會寫入這個檔案，手動修改也會即時套用。

## 資料與行為

- Window entry 在 shell 啟動時讀取模式並呼叫 `Idle.setIdleMode`，同時同步 stock
  `Persistent.states.idle.inhibit` 旗標。
- full 使用 stock Wayland idle inhibitor，hypridle 不會偵測到閒置。完整重啟 shell
  後，inhibitor 會在 surface 顯示約 3 秒後重建，因為 Hyprland 不會套用 surface
  map 之前就建立的 inhibitor（見實作說明）。
- half 與 off 讓 hypridle 照常運作；只有檔案寫 `"off"` 時 gate script 才會休眠
  （檔案缺少、無法讀取或值無效時也視為 `"off"`）。
- `idle-mode-gate.sh suspend --dry-run` 只印出判斷結果，不會休眠。

## 限制

- classic 風格快捷按鈕沒有 patch：會切換模式，但只有 full 會顯示高亮。
- 調整鎖屏或關螢幕時間仍需編輯 `hypridle.conf`。
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
iimod validate modules/idle_modes
iimod check modules/idle_modes
```

`tools/idle-inhibit-probe/probe.sh` 會詢問 compositor 目前是否有 idle inhibitor
生效，輸出 `INHIBITED`、`NOT_INHIBITED` 或 `INCONCLUSIVE`（8 秒偵測期間有輸入）。
要驗證重啟路徑：把 `mode` 設為 `"full"`，用 `qs -c ii kill` 停掉 shell 並從
Hyprland 重新啟動 `qs -c ii`，等 window 模塊載入完成後再執行 probe。
