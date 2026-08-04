# network_traffic — IIMP 參考模塊

Bar 上下行流量計（Tier A，零 stock 補丁）。即時速率、開機/本日/本月累計、
動態刻度貝茲趨勢曲線、per-app 佔用排行（nethogs）、高流量呼吸動效。

## 互動

| 操作 | 效果 |
|---|---|
| hover bar 元件 | 開啟彈窗：速率、ping、累計、趨勢圖、Top app |
| 左鍵點 bar 元件 | 切換統計範圍：本次開機 → 今日 → 本月（全系統與 per-app 排行同步切換） |
| 右鍵點 bar 元件 | 展開/收合 Top 5 應用排行（顯示所選範圍的累計量） |

顏色跟隨 Material You 主題（下載 `colPrimary`、上傳 `colTertiary`），
換壁紙自動變。任一方向速率 ≥ 呼吸門檻（預設 1 MiB/s，可調）時該箭頭呼吸閃爍。

彈窗的 ping 列每 3 秒測一次，只在彈窗開啟時執行。目標預設 `auto`＝主機設定的
DNS（解析 `resolvectl dns` / `resolv.conf`，跳過 loopback stub 與 tailscale
魔法解析器，公網位址優先），可在設定頁改成任意主機。

彈窗頂部的訊號圖示：stock `Network` 服務只在 nmcli 連線事件時刷新，訊號漂移
不觸發——所以彈窗開啟期間每 5 秒輪詢一次公開的 `Network.update()`，圖示隨即時
強度換檔，換檔時帶滑動淡入動效。

## 依賴

`nethogs` 宣告在 `requires.system`——`iimod check`/`install` 缺它時會直接提示安裝指令。
per-app 統計以 nethogs **常駐取樣**（`-t -C -v 2` 累計模式；pcap，TCP+UDP 全計），
delta 累加進開機/今日/本月三桶並持久化，每分鐘至多寫盤一次。nethogs 能歸屬到 process 的流量
以應用程式名記帳；它回報的 synthetic `unknown UDP/0/0` 與 `unknown TCP/0/0` 則分別保留為
「Unattributed UDP」與「Unattributed TCP」，不猜測或灌進同一 snapshot 的 Spotify 等應用。
已觀測但在 process 消失、counter shrink、停用或 ownership handoff 前仍未解析 comm 的 delta，則 exactly-once
歸入「Unattributed process」。具名應用追蹤上限 30 個，長尾摺疊進「其他」；三類 unattributed bucket
獨立保留。
bar slot 會按螢幕各建立一份 UI，但只有 `Quickshell.screens[0]` 的 primary instance 啟動 nethogs、
累加與寫盤；其他螢幕只讀同一份 watched state，避免多個 collector 重複擷取同一介面並競相覆寫記帳。
彈窗摘要使用所選範圍的完整 attributed + unattributed 排名計算占比，右鍵展開時只顯示該排名前五名。
1.5.1 修正 collector 缺少 `-C` 而漏算 UDP／QUIC，以及 process 離開 snapshot 後沿用舊
cumulative baseline、同 PID／command 重現時形成假流量尖峰；同時讓 unresolved PID／comm
cache 隨 process 生命周期清理並重試忙碌中的 `ps` 查詢，且跨日／跨月時先滾動「其他」桶，
避免新週期流量落進過期 bucket。1.5.2 進一步保留 nethogs 無法歸屬 process 的 TCP/UDP bytes，
並將新安裝的統計範圍預設改為今日。若 nethogs 執行失敗（例如 binary 沒有 file capabilities），
runtime 自動降級為 `ss -tinp` 輪詢（僅 kernel TCP，UI 會標「僅 TCP」）。
可在設定頁關閉整個 per-app 統計（筆電省電）。

已知限制：userspace 取樣器只能統計「shell 在看著」的期間——開機到 shell 啟動之間、
以及 shell 沒跑的時段不會入帳（任何非 root/eBPF 常駐方案皆然）。`-C` 讓 nethogs 擷取
TCP 與 UDP，但 nethogs 無法把所有封包歸屬到 process；這些 bytes 會誠實列為 Unattributed，
因此 attributed 應用排名不是線路總量的完整應用歸因。短於取樣間隔便開始並結束的流量仍可能漏掉；
降級 `ss` 時只涵蓋仍存在的 kernel TCP socket，不含 UDP。模塊不會啟動 root daemon，亦不使用
eBPF 或 `ss` 反推 unattributed 流量。無 root 抓包：

```bash
sudo setcap 'cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+ep' /usr/bin/nethogs
```

## 安裝

```bash
iimod validate network_traffic/
iimod check network_traffic/
iimod install network_traffic/     # 或先 iimod pack 再裝 .iimod
```

## 設定

`~/.config/illogical-impulse/modules/network_traffic.json`：

| Key | 預設 | 說明 |
|---|---|---|
| `updateInterval` | 2000 | 輪詢間隔（毫秒） |
| `excludeRegex` | `^(lo\|docker.*\|veth.*\|br-.*\|virbr.*\|tun.*\|tap.*\|wg.*\|tailscale.*\|CloudflareWARP)$` | 排除的介面（隧道/容器預設排除，VPN 不重複計算） |
| `displayMode` | `auto` | `auto` / `stacked`（雙行）/ `horizontal`（單行） |
| `autoStackMaxWidth` | 1920 | `auto` 模式下，螢幕寬度 ≤ 此值時改用雙行 |
| `stackedShowIcons` | `true` | 雙行時是否顯示方向箭頭 |
| `statsPeriod` | `today` | 彈窗統計範圍（`boot` / `today` / `month`；左鍵點 bar 元件循環切換，自動持久化） |
| `statsPeriodSchema` | `1` | 一次性預設遷移標記：舊版未標記的 `boot` 預設升級為 `today`；之後使用者主動選 `boot` 不再覆寫 |
| `appMonitoring` | `true` | per-app 常駐統計；關閉即隱藏彈窗應用區塊、不啟動任何取樣程序 |
| `pingHost` | `auto` | 彈窗 ping 目標；`auto`＝主機設定的 DNS（公網優先），可填任意主機/IP |
| `breatheThresholdKB` | `1024` | 箭頭呼吸門檻（KiB/s），該方向速率達標時呼吸閃爍 |

`acctState` / `appAcctState` 是模塊自管的統計狀態（今日/本月累計、上次取樣點、
per-app 記帳），各自是**單一 JSON 字串**、單次賦值寫入——分欄位儲存曾在熱重載
時被讀到撕裂快照，造成「本月 < 今日」；單 blob 讓撕裂在結構上不可能。
每分鐘至多寫回一次，不是使用者設定。月 ≥ 日不變量在載入與累加時強制鉗制，
壞掉的舊資料會自我修復。

`statsPeriodSchema: 1` 只遷移舊版沒有 schema 的預設選擇，不改動 `acctState` / `appAcctState`；
升級後既有開機、今日與本月記帳會原樣載入並按既有邊界修復規則延續。

全部選項在設定 app 的 **Modules → Network Traffic** 頁有對應控件。

### 為什麼預設要雙行

ii 的 bar 右區是 `anchors { left: middleSection.right; right: parent.right }` 加
`layoutDirection: Qt.RightToLeft` 的 RowLayout。中間區用 `barCenterSideModuleWidth`
**固定**預留（`bar.verbose` 開啟時每側 360px），不隨螢幕縮放；右區內容一旦超出剩餘寬度，
就會往左溢出並蓋在 stock 元件上，而不是被裁切。

1920×1200、`bar.verbose: true`、10 個 workspace 的實測：

```
中間區 996px  →  右區可用 461px
右區需求 576px（指示器 153 + 托盤 110 + 本模塊 171 + 天氣 88 + 間距 42）
                                       溢出 115px
```

單行版 171px 是右區最寬的單一元件。雙行版約 58px，剛好把溢出補平。
寬螢幕不受這個限制，所以 `auto` 只在窄螢幕上壓縮。

**支援四種 bar 位置**：上/下（水平，單行或雙行版面）、左/右（垂直，
無箭頭、純色彩編碼的直向數值，自動適配 45px 窄膠囊；彈窗改為寬扁雙欄，
避開 stock 彈窗無邊緣夾取的裁切）。垂直 bar 的載入圍欄由 iimod ≥1.1 的
host P5 提供，位置在頂段的留白區（水平 bar 放視窗標題的位置）——頂段高度
天生等於「中段以上的剩餘空間」，模塊在此結構上不可能與置中的時鐘/電池相撞。

字級不寫死，從 `baseBarHeight` 反推（膠囊高 = `baseBarHeight - 8`，行高 =
`floor((膠囊高 - 6) / 2)`，字級 = `clamp(行高 - 2, 9, small)`），因此改 bar 高度或
cornerStyle 時內容不會超出膠囊。

## 從舊手工補丁版遷移

若你先前手動安裝過（`services/NetworkTraffic.qml` ＋ BarContent/Config/BarConfig 補丁）：

1. 舊設定對照：`config.json` 的 `bar.networkTraffic.updateInterval` / `excludeRegex` → 搬到上表的模塊設定檔；`bar.networkTraffic.enable` → 由 `iimod enable/disable` 或設定 app 的 Modules 頁控制
2. 移除手工補丁（或等下次 dots 更新自然沖掉後 `iimod reapply`）再 `iimod install`
3. 手工版在 `config.json` 留下的 `bar.networkTraffic` 區塊會被 shell 的 JsonAdapter 自動剝掉，無需清理

## 實作說明（給模塊作者的參考）

- `TrafficLogic.qml`：輪詢邏輯**實例**（非單例——IIMP 模塊禁用 pragma Singleton），由 `bar.qml` 建立並向下傳遞；今日/本月累計以 delta 累加（`/proc/net/dev` 計數器縮小＝重開機，該段遺失是設計取捨）
- `AppTraffic.qml`：per-app 常駐取樣器＋記帳（隨 bar 元件生滅，不是隨彈窗）；nethogs 用 `-C -v 2` 擷取 TCP+UDP 累計 bytes 再取 delta、需 `stdbuf -oL`（接管道時會整塊緩衝）；synthetic unknown TCP/UDP 使用穩定 unattributed identity，保留方向與 cumulative delta 而不猜測應用歸屬；每個 refresh 只保留當次仍存在且計數器連續的 process identity，counter shrink 會清除 PID comm/pending 並重新解析；`/proc/self/exe` 型程式名先把 delta 暫存，等 `ps` 解析出 comm 再入帳，若在停用、銷毀或 ownership handoff 前仍無法解析，已觀測 bytes 會 exactly-once 歸入 Unattributed process；boot 桶以 `/proc/sys/kernel/random/boot_id` 判斷換機重置
- `BezierGraph.qml`：Catmull-Rom → 貝茲曲線 Canvas，視窗最大值即滿刻度並以小字標註
- `ConfigLoader.qml`：FileView＋JsonAdapter 寫自己的設定檔，永不碰 shell 的 `config.json`；每個 adapter 變更只記錄欄位 intent，寫入前同步 reload 最新原始 JSON，再以原子 `setText()` 合併，故 settings instance 仍可保存使用者設定，但只有 owner lease 可改 accounting blobs，stale secondary snapshot 不會覆寫新統計
- `bar.qml`：以 `BarGroup` 為根自帶藥丸外觀；固定欄寬防抖動（TextMetrics）；版面用「每個方向一個獨立 RowLayout」而非共用四格 GridLayout——GridLayout 會**跳過** `visible: false` 的項目而不是保留格位，箭頭一關兩行就會錯位
- `ConfigLogic.js`：materialize 當前 schema 的缺失預設值並保留未知 JSON 欄位；遇到 future `statsPeriodSchema` 時不覆寫原文或套用當前 adapter 預設，後續使用者欄位更新也在 future 原文上 merge
- 每個用到的 stock API（BarGroup、StyledPopup、Graph、Network 服務）都在 manifest 宣告了探針
