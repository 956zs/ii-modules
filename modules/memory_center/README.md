# memory_center — 記憶體中心

視覺化 RAM/swap 檢視與清理工具（Tier B，一個側欄磁貼補丁）。不是清單式監控看板：
組成一目了然的比例條 + treemap 式程序方塊，外加兩個真正有用的清理動作。

## 互動

| 操作 | 效果 |
|---|---|
| hover bar 元件 | 彈窗：使用率、組成迷你條（應用程式／快取與緩衝／可用）、swap 一行 |
| 點 bar 元件／側欄磁貼（或 IPC） | 開啟/關閉詳細面板 |
| 面板：點程序方塊 | 自己的程序→武裝（變紅），再點一次→送 SIGTERM；別人的程序只顯示資訊 |
| 面板：整理 swap | `swapoff -a && swapon -a`（需認證；swap 空或可用 RAM 不足時停用並附說明） |
| 面板：清除快取 | `sync; echo 3 > /proc/sys/vm/drop_caches`（需認證） |

Bar 元件顏色跟隨 Material You：正常為文字色，使用率超過警示門檻（預設 85%，可調）
後線性漂向 error 色——即使關掉百分比只留圖示，壓力狀態仍看得到。

## 隱藏 bar 元件（省 bar 空間）

多模塊同時佔 bar 右區時空間吃緊，且 stock 的 Resources 元件本來就有記憶體儀表。
設定 `showBar: false`（設定 app 有開關）即可隱藏 bar 藥丸——host layout 會跳過
不可見子項，不留幽靈間距。IPC handler 與面板 LazyLoader 都掛在 bar entry 內、
不隨可見性銷毀，面板仍可從側欄磁貼或 IPC 開啟。bar 元件隱藏且面板關閉時
`/proc/meminfo` 輪詢完全停止，重新開啟面板時立即補採一次樣。

## 側欄磁貼（Tier B 補丁）

安裝時在 stock 的 `AndroidToggleDelegateChooser.qml`（`antiFlashbang` 錨點前）
插入一個 `DelegateChoice`，包裝 stock `AndroidQuickToggleButton`（圖示
`memory`），點擊經 `execDetached` 呼叫本模塊 IPC 開啟面板——manifest 宣告
`exec` 的另一個原因。多個模塊可在同一錨點並存（依模塊 id 排序）。

內建磁貼編輯器只提供原生類型，**不會**列出本模塊的磁貼。安裝後請手動把
下列項目加入 `~/.config/illogical-impulse/config.json` 的
`sidebar.quickToggles.android.toggles` 陣列（`size: 2` 可換寬版，顯示名稱）：

```json
{"type": "memory_center", "size": 1}
```

設定 app 的 **Modules → Memory Center** 頁也有這行可直接複製。移除磁貼即從
陣列刪掉該項；`iimod uninstall` 後殘留的該項只會被 DelegateChooser 靜默略過。

## 誠實的組成分類

疊加條的三段不是把 `Cached+Buffers+SReclaimable` 加起來（`Cached` 含不可回收的
shmem，直接相加會重複計算、高估可回收量），而是恆等式拆分：

```
應用程式（使用中） = MemTotal − MemAvailable   ← 核心真正給不出來的部分
快取與緩衝（可回收）= MemAvailable − MemFree    ← 壓力下核心會回收的 page cache/buffers/slab
可用               = MemFree
```

三段總和恆等於 `MemTotal`，比例條永遠不說謊。程序方塊為 flow-treemap：
列高∝該列 RSS 佔比、方塊寬∝列內佔比，**面積全域正比於 RSS**；
超出設定數量的長尾摺疊進「其他」。

## 誠實的 drop_caches 說明

快取是效能的朋友：核心在記憶體吃緊時本來就會自動回收快取，`drop_caches`
不會「變出」可用記憶體，主要用途是量測（benchmark 前歸零快取狀態）。
面板照做也照說——執行後重新取樣並回報 **實測** 的 `MemFree` 增量，
不假裝這是省下來的記憶體。「整理 swap」則在記憶體壓力解除後把滯留 swap 的
頁面搬回 RAM，這是真正有感的動作；當 swap 為空或可用 RAM < swap 佔用
（swapoff 會反覆換頁）時按鈕停用並以 tooltip 說明原因。

## Root 認證機制

清理動作經 `pkexec sh -c '…'` 執行：illogical-impulse shell **內建 polkit
agent**（`modules/ii/polkit`，`module.json` 有對應 probe），會彈出全螢幕認證
對話框。pkexec 失敗（且非使用者按取消，exit 126）時退回嘗試一次
`sudo -A sh -c '…'`（askpass，需自行設定 `SUDO_ASKPASS`）；兩者都失敗則把
stderr 原文顯示在面板內。不重試、不背景靜默執行。

## 資料來源與成本

- `/proc/meminfo`：FileView 直讀（零 capability 語意；預設 2 秒，bar 與彈窗共用）。
- `ps -eo pid,euser,rss,comm --sort=-rss`：**只在面板開啟時** 輪詢（預設 4 秒），
  關閉即停。kernel thread（RSS 0）過濾。
- SIGTERM 只提供給 `euser == $USER` 的程序；kill 用 `kill -15`，無 root。

## 安裝

```bash
iimod validate memory_center/
iimod check memory_center/
iimod install memory_center/ --allow-patches   # Tier B：側欄磁貼補丁需明示允許
```

測試鉤子：`qs -c ii ipc --any-display call memory_center toggle` 開關面板。

## 設定

`~/.config/illogical-impulse/modules/memory_center.json`：

| Key | 預設 | 說明 |
|---|---|---|
| `showBar` | `true` | 顯示 bar 元件；關閉省 bar 空間，面板仍可從側欄磁貼／IPC 開啟 |
| `meminfoInterval` | 2000 | /proc/meminfo 輪詢間隔（毫秒） |
| `procInterval` | 4000 | 面板開啟時 ps 輪詢間隔（毫秒） |
| `showBarPercent` | `true` | bar 上顯示百分比（關閉只留圖示） |
| `blockCount` | 12 | 面板程序方塊數，長尾摺疊進「其他」 |
| `warnPercent` | 85 | 使用率超過此值 bar 開始警示變色 |
