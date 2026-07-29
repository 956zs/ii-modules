# memory_center - 記憶體中心

Tier B RAM/swap 檢視與清理工具。提供可隱藏的 bar 狀態、hover 組成摘要、
RSS treemap 程序面板，以及需認證的 swap 整理與 page-cache 清理。

側欄整合是一項功能，但由兩個 insert-only patches 組成：磁貼 delegate，以及
編輯模式的新增／重新加入列。

> [!WARNING]
> 結束程序會送出 `SIGTERM`。整理 swap 與清除 cache 是需系統管理員認證的
> 全系統操作；請先理解影響，不要把 cache 釋放量當成永久節省的記憶體。

## 需求

| 工具 | 用途 | 必要性 |
|---|---|---|
| `ps` | 面板開啟時取樣 top processes | `iimod check/install` 必要 |
| `pkexec` | 執行需認證的 cleanup actions | `iimod check/install` 必要 |
| shell polkit agent | 顯示 `pkexec` 認證 UI | stock ii 提供並由 probe 驗證 |
| `sudo -A` | `pkexec` 非取消失敗時的一次 fallback | 可選，需 `SUDO_ASKPASS` |
| `sh`, `sync`, `swapoff`, `swapon` | 執行 cleanup script | 使用對應 action 時需要 |
| `id`, `kill` | 辨識使用者並送出 `SIGTERM` | 程序操作時需要 |

模塊宣告 `exec` capability。它不會無提示重試或在背景靜默執行 privileged action。

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/memory_center/
iimod check modules/memory_center/
iimod install modules/memory_center/ --allow-patches
```

## 互動

| 操作 | 效果 |
|---|---|
| Hover bar 元件 | 顯示使用率、組成迷你條與 swap 摘要 |
| 點擊 bar 元件、側欄磁貼或 IPC | 切換詳細面板 |
| 點自己的程序方塊兩次 | 武裝後送出 `SIGTERM` |
| 點別人的程序方塊 | 只顯示資訊，不提供結束動作 |
| 整理 swap | 認證後執行 `swapoff -a && swapon -a` |
| 清除快取 | 認證後執行 `sync; echo 3 > /proc/sys/vm/drop_caches` |

IPC 入口：

```bash
qs -c ii ipc --any-display call memory_center toggle
```

## Bar 與側欄

`showBar: false` 會讓 host layout 跳過 bar 元件，不留下空白。IPC handler 與 detail
panel 仍可使用；bar 隱藏且面板關閉時，`/proc/meminfo` 輪詢也會停止。

快速開關編輯模式會在磁貼缺席時，於「未使用」區提供 `memory_center`。舊版 shell
可手動把以下項目加入 `sidebar.quickToggles.android.toggles`：

```json
{"type": "memory_center", "size": 1}
```

移除磁貼與卸載模塊是兩件事。卸載後，殘留的 config 項目只會被 stock delegate
忽略；建議一併從快速開關設定移除。

## 設定

設定檔位於：

```text
~/.config/illogical-impulse/modules/memory_center.json
```

| Key | 類型 | 預設 | 範圍 | 說明 |
|---|---|---:|---:|---|
| `showBar` | boolean | `true` | - | 顯示 bar 元件 |
| `meminfoInterval` | integer | `2000` | 500-10000 ms | `/proc/meminfo` 輪詢間隔 |
| `procInterval` | integer | `4000` | 1000-15000 ms | 面板開啟時的 `ps` 間隔 |
| `showBarPercent` | boolean | `true` | - | 在 bar 顯示百分比 |
| `blockCount` | integer | `12` | 4-24 | 程序方塊數量，長尾摺疊為「其他」 |
| `warnPercent` | integer | `85` | 50-100% | 開始向 error 色過渡的門檻 |

## 資料與行為

### 記憶體組成

模塊使用可驗證的恆等式，不直接相加可能重疊的 `Cached`、`Buffers` 與
`SReclaimable`：

```text
應用程式（使用中） = MemTotal - MemAvailable
快取與緩衝（可回收） = MemAvailable - MemFree
可用 = MemFree
```

三段總和恆等於 `MemTotal`。程序 flow-treemap 的方塊面積全域正比於 RSS，超出
`blockCount` 的長尾合併成「其他」。

### Cleanup actions

`drop_caches` 主要適合 benchmark 前歸零 cache 狀態；Linux 本來會在記憶體壓力下
回收 cache。模塊執行後重新取樣並顯示實測 `MemFree` 增量，不宣稱那是永久節省。

整理 swap 會把 swap pages 搬回 RAM。swap 為空，或 `MemAvailable` 小於 swap
使用量時，按鈕會停用以避免反覆換頁。

認證先嘗試 `pkexec sh -c ...`。使用者取消（exit 126）時立即停止；其他失敗才嘗試
一次 `sudo -A sh -c ...`，兩者失敗時在面板顯示錯誤。

### 取樣成本

- `/proc/meminfo` 由 `FileView` 讀取，bar 與 popup 共用。
- `ps -eo pid,euser,rss,comm --sort=-rss` 只在面板開啟時執行。
- kernel threads（RSS 0）會被過濾。
- 只有 `euser == $USER` 的程序能從面板送出 `kill -15`。

## 相容性與限制

模塊在 dots commit `446504ad42`、Quickshell `0.2.1` 測試。兩個 sidebar patches
依賴 stock delegate 與 unused-row 錨點；上游改動錨點時，`iimod check` 會拒絕套用。

Treemap 顯示 RSS，不等於 process 的完整 PSS 或所有 shared-memory 成本。Cleanup
結果受當時 workload、kernel reclaim 與 swap 狀態影響。

## 卸載與資料

```bash
iimod uninstall memory_center
```

卸載會移除 bar/side-panel integration 並還原 stock QML，但不會刪除：

```text
~/.config/illogical-impulse/modules/memory_center.json
```

不再需要設定時可由使用者自行移除該檔，並從 sidebar quick-toggle config 刪除殘留項目。
