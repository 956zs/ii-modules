# network_traffic - 網路流量

Tier A bar 流量計，不修改 stock QML。提供即時上下行速率、DNS ping、
開機／今日／本月累計、動態刻度趨勢圖，以及 best-effort per-app 排行。

全系統流量讀取 `/proc/net/dev`。per-app 統計依序嘗試 `pktz`、`nethogs`
與 `ss`；介面會明確標示目前資料來源與降級後的涵蓋範圍。

## 互動

| 操作 | 效果 |
|---|---|
| Hover bar 元件 | 顯示速率、ping、累計、趨勢圖與應用摘要 |
| 左鍵點擊 | 在開機、今日、本月三種統計範圍間切換 |
| 右鍵點擊 | 展開或收合所選範圍的 Top 5 應用排行 |

下載使用 Material You `colPrimary`，上傳使用 `colTertiary`。任一方向達到
呼吸門檻時，對應箭頭會播放呼吸動效。

彈窗開啟期間：

- 每 3 秒測量一次 ping。
- 每 5 秒呼叫 stock `Network.update()`，更新連線類型與 Wi-Fi 訊號圖示。
- `pingHost: auto` 優先使用主機設定的公網 DNS，並跳過 loopback stub 與
  Tailscale magic DNS。

彈窗關閉時會停止 DNS discovery 與正在進行的 ping；延遲測試不會在背景持續執行。

## 需求與資料來源

`nethogs` 是 `module.json` 中的 install-time 必要依賴，也是宣告的 per-app fallback；
`iimod check/install` 只驗證它存在於 `PATH`，不保證 runtime 抓包權限或輸出可用。
`pktz` 是可選的 preferred backend；IIMP v1 沒有 optional system dependency
欄位，因此未列入 `requires.system`。

| 分類 | 工具 | 用途 |
|---|---|---|
| Install-gated | `nethogs` | 宣告的 per-app fallback |
| Optional preferred | `pktz` | eBPF process payload 統計 |
| Runtime helpers | `stdbuf`, `ss`, `ps`, `qs` | 行緩衝、最終 fallback、名稱解析與 IPC |
| Popup-only | `ping`, `sh`, `resolvectl`, `grep`, `awk` | Ping 與 DNS auto-discovery |

| 順序 | Backend | 彈窗標示 | 涵蓋範圍 | 啟動條件 |
|---:|---|---|---|---|
| 1 | `pktz --log` | eBPF 估算 | TCP payload；UDP RX 與 IPv6 UDP TX 視 upstream probes 而定 | Binary 存在且 eBPF probes、權限可用 |
| 2 | `nethogs -t -C -v 2` | pcap | TCP/UDP；特定 synthetic unknown rows 另列 | `pktz` 無法啟動或退出 |
| 3 | `ss -tinpH` | 僅 TCP | 仍存在的 kernel TCP sockets | `nethogs` 啟動失敗、退出或逾時無可用 snapshot |
| 4 | unavailable | 無 | Per-app 區塊無新資料 | `ss` 非零退出 |

模塊依序在 `$PATH`、`$HOME/go/bin/pktz`、`$HOME/.local/bin/pktz` 尋找
`pktz`，以涵蓋未繼承互動 shell `PATH` 的 Quickshell session。本文描述的 NDJSON、
probe coverage 與 log-tick 行為以 `pktz 0.1.0` 實測為準；其他版本屬 best-effort。
切換 backend 只重建記憶體中的 baseline，不會清空既有 `appAcctState`。

### 一次性權限設定

模塊宣告 `exec` capability，但不會呼叫 `sudo`、啟動 root daemon，或自行修改
binary capabilities。需要 rootless 取樣時，由使用者一次性設定 file capabilities。

`pktz`：

```bash
PKTZ="$HOME/go/bin/pktz"  # or another discovered pktz binary
sudo setcap 'cap_bpf,cap_perfmon,cap_dac_read_search+ep' "$PKTZ"
```

Runtime 也會檢查 `$HOME/.local/bin/pktz`，可依實際安裝位置調整 `PKTZ`。

`nethogs`：

```bash
sudo setcap 'cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+ep' \
  /usr/bin/nethogs
```

## 安裝

從 repository 根目錄執行：

```bash
iimod validate modules/network_traffic/
iimod check modules/network_traffic/
iimod install modules/network_traffic/
```

## 設定

設定檔位於：

```text
~/.config/illogical-impulse/modules/network_traffic.json
```

| Key | 預設 | 說明 |
|---|---:|---|
| `updateInterval` | `2000` | `/proc` 與 `ss` 輪詢、四捨五入後的 `nethogs -d`，以及 nethogs 啟動 timeout 基準；不控制 pktz upstream tick |
| `excludeRegex` | 見設定檔 | 排除 loopback、容器、隧道等介面，避免 VPN 重複計算 |
| `displayMode` | `auto` | `auto`、`stacked` 或 `horizontal` |
| `autoStackMaxWidth` | `1920` | `auto` 模式切換成雙行版面的最大螢幕寬度 |
| `stackedShowIcons` | `true` | 雙行版面是否顯示方向箭頭 |
| `statsPeriod` | `today` | `boot`、`today` 或 `month`；左鍵點擊時循環切換 |
| `statsPeriodSchema` | `1` | 內部遷移標記，不是一般使用者選項 |
| `appMonitoring` | `true` | 是否啟動 per-app 取樣與顯示應用區塊 |
| `pingHost` | `auto` | Ping 主機名稱或 IP；`auto` 使用主機 DNS |
| `breatheThresholdKB` | `1024` | 箭頭呼吸門檻，單位為 KiB/s |

**Settings > Modules > Network Traffic** 提供更新間隔、版面、圖示、per-app
監控、ping 目標與呼吸門檻控件。`statsPeriod` 由 bar 左鍵切換；`excludeRegex`
目前只能在設定檔調整。

> [!NOTE]
> `acctState`、`appAcctState` 與 `statsPeriodSchema` 是模塊管理的持久狀態，
> 不應手動編輯。

## 資料與記帳行為

### 全系統統計

`TrafficLogic.qml` 從 `/proc/net/dev` 讀取累計 counters，再以相鄰樣本 delta
計算速率與今日／本月累計。counter 縮小視為重開機或資料來源重置；該段差值不猜測。

預設排除 loopback、容器與隧道介面，以免 VPN 流量同時出現在實體介面與 tunnel。
使用者可用 `excludeRegex` 調整範圍。

### Per-app 統計

`pktz` process NDJSON 以 timestamp 分 frame。只有看到下一個 timestamp 時，前一個
frame 才視為封口並提交；EOF、主動停止或 ownership handoff 會捨棄未封口的最後一批，
最多損失一個 log tick，但不會把 partial frame 當成完整 snapshot。

`nethogs` 與 `pktz` 都以 cumulative counters 的相鄰 delta 記帳。以下事件只建立
新 baseline，不產生流量尖峰：

- 首次觀測 process
- counter 縮小
- collector 重啟
- process command 改變
- process 從可觀測 snapshot 消失後重新出現

記帳分類如下：

| 分類 | 來源與規則 |
|---|---|
| 具名應用 | 可解析 process identity 的流量；最多保留 30 個名稱 |
| 其他 | 超出具名應用上限的長尾流量 |
| Unattributed TCP | `nethogs` 的 synthetic `unknown TCP/0/0` |
| Unattributed UDP | `nethogs` 的 synthetic `unknown UDP/0/0` |
| Unattributed process | 已有 delta，但在結束、重置或 handoff 前仍無法解析 command |

模塊不會把 unattributed bytes 猜測成同一 snapshot 中的 Spotify 或其他應用。
彈窗摘要以所有保留的 per-app buckets 計算占比；展開時只顯示前五名。這不代表
所有線路流量都能歸屬到具名應用。

### 持久化與單寫入者

`acctState` 與 `appAcctState` 各自儲存為單一 JSON 字串，並以單次賦值寫入，避免
熱重載期間讀到跨欄位撕裂快照。一般累加會節流寫入；初始化、修復、週期滾動、
停止、銷毀、ownership handoff 與設定 intent 可立即寫入。載入與累加時會維持
「本月累計不小於今日累計」的不變量。

bar slot 會在每個螢幕建立 UI，但只有 `Quickshell.screens[0]` 的 primary instance
啟動 collector、累加與寫盤。其他 bar instance 與獨立 Settings process 都是 watched
reader；設定變更透過 argv-safe `qs ipc call` 傳給 primary，經 key、type、range
allowlist 驗證後，與 accounting 在同一 process 串行寫入。

### 統計範圍遷移

schema 1 會把任何舊版未標記或 schema 0 的 `boot` 選擇遷移成 `today`；舊格式沒有
足夠資訊區分預設值與使用者主動選擇。完成遷移後，使用者再次選擇 `boot` 不會被
覆寫，既有開機／今日／本月統計 blob 也不會因遷移而清空。

## 版面行為

`displayMode: auto` 在螢幕寬度不大於 `autoStackMaxWidth` 時使用雙行版面。這是為了
避免 stock bar 中央區固定預留寬度後，右側 RowLayout 內容向左溢出。

以 1920x1200、`bar.verbose: true`、10 個 workspace 的量測為例：

```text
中間區 996 px -> 右區可用 461 px
右區需求 576 px
預估溢出 115 px
```

單行元件約 171 px，雙行約 58 px。垂直 bar 則使用無箭頭、色彩編碼的直向數值，
彈窗改成寬扁雙欄；字級與行高從 `baseBarHeight` 推導，不寫死固定尺寸。

## 限制

- Per-app collector 只統計 shell 運行期間；開機到 shell 啟動前，以及 shell 停止期間
  不入帳。全系統 `/proc/net/dev` 統計會在目前 counters 不小於持久化 sample 時補上
  shell 停止期間的 delta，但沒有保存 boot ID 或 sample timestamp：重開機後 counters
  已超過舊 sample 時可能誤判為連續，跨日／跨月 gap 也會全數記在重啟當下週期。
- `pktz` 計算 process socket payload，不含 headers 與 TCP 線路重傳，因此不應與
  `/proc/net/dev` 逐 byte 相等。
- `pktz` upstream 的 UDP RX 與 IPv6 UDP TX probes 是 optional；attach 失敗時可能
  靜默降低涵蓋率。
- `pktz --log` 沒有 heartbeat、empty-frame、exit record 或 schema version。健康但
  沒有 process 時可以完全沉默，因此模塊只在 process 退出時 fallback。
- `pktz` upstream identity 只有 PID。模塊增加 command、counter 與 snapshot barrier，
  但相同 PID／command 若在沒有非空中間 snapshot 時重用，protocol 仍無法辨識。
- 在第一個 500 ms log tick 前開始並結束的 process 可能不會出現在 `pktz` snapshot。
- `nethogs` 只把精確 synthetic rows `unknown TCP/0/0` 與 `unknown UDP/0/0`
  保留為 Unattributed；其他無法辨識的 `unknown <protocol>` 形式會被丟棄。具名應用
  排行因此不是線路總量的完整歸因。
- `nethogs` 可能漏掉短於取樣間隔的完整連線；`ss` fallback 只涵蓋仍存在的 TCP socket，
  不含 UDP。

## 從舊手工補丁版遷移

若曾手動安裝 `services/NetworkTraffic.qml` 與 stock QML 補丁：

1. 將 `config.json` 的 `bar.networkTraffic.updateInterval` 與 `excludeRegex` 搬到
   模塊設定檔。
2. 以 `iimod enable/disable network_traffic` 取代舊的
   `bar.networkTraffic.enable`。
3. 移除手工補丁，或等 dots 更新還原 stock 後，再執行 `iimod install`。

stock JsonAdapter 會在後續寫入 `config.json` 時移除不再宣告的舊
`bar.networkTraffic` 區塊，無需為遷移立即手動清理。

## 實作說明

| 檔案 | 職責 |
|---|---|
| `TrafficLogic.qml` | `/proc/net/dev` 輪詢、速率與全系統累計 |
| `AppTraffic.qml` | Backend lifecycle、per-app baseline、rate 與 accounting |
| `AppTrafficLogic.js` | 純 NDJSON/nethogs parsing 與 snapshot 計算 |
| `ConfigLoader.qml` | 設定讀取、primary-only 寫入與 watched-reader 狀態 |
| `ConfigRequest.qml` | FIFO、argv-safe、有界 retry 的 IPC 設定請求 |
| `ConfigLogic.js` | 設定 materialization、allowlist 驗證與 future-schema 保留 |
| `BezierGraph.qml` | Catmull-Rom 到 Bezier 的動態刻度 Canvas |
| `bar.qml` | `BarGroup` 外觀、固定欄寬與水平／垂直版面 |

所有非 baseline stock API 都在 `module.json` 宣告 probe。邏輯物件由 entry component
建立並向下傳遞；模塊不使用 `pragma Singleton`。

## 開發驗證

```bash
node --test modules/network_traffic/tests/*.test.mjs
python -m py_compile modules/network_traffic/tests/pktz-live-smoke.py
iimod validate modules/network_traffic/
iimod suggest modules/network_traffic/
iimod check modules/network_traffic/
```
