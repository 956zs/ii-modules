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
per-app 統計以 nethogs **常駐取樣**（`-t -v 2` 累計模式；pcap，TCP+UDP 全計，QUIC 不漏），
delta 累加進開機/今日/本月三桶並持久化，每分鐘至多寫盤一次；追蹤上限 30 個 app，
長尾摺疊進「其他」。若 nethogs 執行失敗（例如 binary 沒有 file capabilities），
runtime 自動降級為 `ss -tinp` 輪詢（僅 kernel TCP，UI 會標「僅 TCP」）。
可在設定頁關閉整個 per-app 統計（筆電省電）。

已知限制：userspace 取樣器只能統計「shell 在看著」的期間——開機到 shell 啟動之間、
以及 shell 沒跑的時段不會入帳（任何非 root/eBPF 常駐方案皆然）。無 root 抓包：

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
| `statsPeriod` | `boot` | 彈窗統計範圍（左鍵點 bar 元件循環切換，自動持久化） |
| `appMonitoring` | `true` | per-app 常駐統計；關閉即隱藏彈窗應用區塊、不啟動任何取樣程序 |
| `pingHost` | `auto` | 彈窗 ping 目標；`auto`＝主機設定的 DNS（公網優先），可填任意主機/IP |
| `breatheThresholdKB` | `1024` | 箭頭呼吸門檻（KiB/s），該方向速率達標時呼吸閃爍 |

`acctState` / `appAcctState` 是模塊自管的統計狀態（今日/本月累計、上次取樣點、
per-app 記帳），各自是**單一 JSON 字串**、單次賦值寫入——分欄位儲存曾在熱重載
時被讀到撕裂快照，造成「本月 < 今日」；單 blob 讓撕裂在結構上不可能。
每分鐘至多寫回一次，不是使用者設定。月 ≥ 日不變量在載入與累加時強制鉗制，
壞掉的舊資料會自我修復。

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
- `AppTraffic.qml`：per-app 常駐取樣器＋記帳（隨 bar 元件生滅，不是隨彈窗）；nethogs 用 `-v 2` 累計模式取 delta、需 `stdbuf -oL`（接管道時會整塊緩衝）；`/proc/self/exe` 型程式名先把 delta 暫存，等 `ps` 解析出 comm 再入帳，避免 Electron app 被記成「exe」；boot 桶以 `/proc/sys/kernel/random/boot_id` 判斷換機重置
- `BezierGraph.qml`：Catmull-Rom → 貝茲曲線 Canvas，視窗最大值即滿刻度並以小字標註
- `ConfigLoader.qml`：FileView＋JsonAdapter 寫自己的設定檔，永不碰 shell 的 `config.json`；`ready` 旗標讓統計初始化等檔案真正載入（FileView 是非同步的）
- `bar.qml`：以 `BarGroup` 為根自帶藥丸外觀；固定欄寬防抖動（TextMetrics）；版面用「每個方向一個獨立 RowLayout」而非共用四格 GridLayout——GridLayout 會**跳過** `visible: false` 的項目而不是保留格位，箭頭一關兩行就會錯位
- `ConfigLoader.qml`：`onLoaded: writeAdapter()` 把合併後的設定寫回檔案。舊版寫的設定檔缺少後來新增的 key，JsonAdapter 對缺失的 key 是回傳型別零值而非 QML 宣告的預設值，不寫回就會讓升級的使用者拿到 `false` / `0`
- 每個用到的 stock API（BarGroup、StyledPopup、Graph、Network 服務）都在 manifest 宣告了探針
