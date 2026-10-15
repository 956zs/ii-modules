# osu! 遊玩狀態指標：需求（2026-10-15）

擁有者要求（10/15）：
- 做一個指標，顯示他是不是正在玩 osu!。
- 「在選歌畫面」和「真的在打一首歌」要分開。
- 這份文件原本只整理需求。2026-10-15 擁有者決定先做第 3、5 節（服務、指令、hook），第 4 節的 ii module 之後另開。

實作狀態（2026-10-15）：
- ✅ 第 2、3、5 節：Rust 專案 `~/Desktop/github/osu-state`，已安裝為 `~/.local/bin/osu-state` 與 `osu-state.service`（user unit，已 enable 並在跑），hook 已註冊到 `~/.claude/settings.json`。
- ✅ 第 4 節 ii module：`modules/osu_indicator` 1.0.0（Tier A bar 模組），2026-10-15 完成並已安裝啟用；打擊圈圖示、approach circle 動畫、計時／倒數文字、hover 彈窗、設定頁（idle/menu 顯示開關、計時、動畫、主題色或 osu 粉）。
- 第 6 節驗收：`idle`、hook deny/allow、`wait-free` 超時、daemon 重啟重放、SIGTERM 刪檔已實測；`menu`、`playing`、`cooldown`、`off` 的即時轉換要等擁有者實際操作 osu 時確認。

起因：Claude 在他打歌時編譯程式，遊戲卡頓。「打開 osu 跟遊玩 osu 是兩回事」：osu!lazer 常常只是開著放在背景。

## 1. 要分辨的狀態

| 狀態 | 意思 | 例子 |
|---|---|---|
| `off` | osu! 沒在跑 | — |
| `idle` | 開著，但不在前景 | 切去 Discord、瀏覽器 |
| `menu` | 在前景，但沒在打歌 | 主選單、選歌、設定、看成績 |
| `playing` | 正在打一首歌（含暫停） | 進入一首圖之後到成績畫面之前 |
| `cooldown` | 剛打完一首，還在連續打歌的節奏裡 | 打完進成績畫面：`playing` 結束後 `grace_secs` 秒內（預設 120）；中途退出、失敗、重試（沒進成績畫面）：`quit_grace_secs` 秒（預設 10） |

`cooldown` 存在的理由：一首接一首打時，兩首之間會回到選歌畫面幾十秒。這段時間不能讓編譯趁機開跑。

2026-10-16 補充（擁有者回饋「中途退出他不會顯示退出」）：中途退出不算連續打歌，只給 `quit_grace_secs` 的短寬限；lazer 打完會寫 `entered SoloResultsScreen`，退出則直接 `exit from SoloPlayer`，daemon 以此分辨。

## 2. 偵測來源

先確認哪個可行，再決定用哪個。2026-10-15 實測結論：用第 1 點加第 5 點，第 2、3 點不需要。

1. **Hyprland 視窗**（已確認可行，已採用）：osu!lazer 的視窗 class 是 `osu!`，全螢幕時 `fullscreen = 2`。用 `hyprctl activewindow` 和 socket2 的 `activewindow` 事件，可以知道它是不是前景。這個來源分得出 `off`、`idle`、`menu`，但分不出打歌和選歌。
2. **視窗標題**（不需要）：選歌畫面時標題是 `osu!`。有第 5 點之後沒有再實測打歌時的標題。
3. **Discord Rich Presence**（實測走不通，不採用）：2026-10-15 這台的 `discord-rpc-proxy.service` 是 inactive（它掛在從未啟動的 `graphical-session.target` 底下），`discord-ipc-0` 由 Discord 本體持有，lazer 的 `DiscordRichPresence = Limited`。原始筆記保留：
   - osu!lazer 會送出 RPC 狀態，例如打歌時顯示「Playing ...」、選歌時顯示「Choosing a beatmap」之類，實際文字要實測。
   - 這台已經有 `discord-rpc-proxy.service`（`~/.local/bin/discord-rpc-proxy`），RPC 會經過它，從那裡就能讀到狀態。
   - 這是官方提供的訊號，不用讀遊戲記憶體。
4. **不考慮讀遊戲記憶體**（像 tosu、gosumemory 那類）：有反作弊疑慮，也太重。
5. **osu!lazer runtime log**（已確認可行，已採用）：`~/.local/share/osu/logs/<啟動時間>.runtime.log` 每行即時 flush，有 `Starting/Ending high performance session`、`entered/suspended/exit from SoloPlayer#N`（ReplayPlayer 同理）和 `Game-wide working beatmap updated to <Artist - Title (mapper) [Diff]>`。五次啟動的 high performance session 配對數和 Player 進出數吻合。暫停不離開 Player 畫面，自然算 `playing`。用 inotify 跟檔。字串沒有相容性承諾，比對不到時退回 `menu`，不會卡在 `playing`。

## 3. 輸出（給其他程式用的介面）

- **狀態檔**：`$XDG_RUNTIME_DIR/osu-state.json`。
  - 內容例如 `{"state": "playing", "since": <unix秒>, "beatmap": "Artist - Title (mapper) [Diff]" 或 null, "cooldown_until": <只在 cooldown 出現>, "updated": <unix秒>, "pid": <daemon PID>}`。
  - 每次狀態改變時用原子寫入（先寫暫存檔再 rename）。daemon 正常結束會刪掉檔案；讀取端發現 `pid` 不存在時把檔案當成不存在。
- **指令** `osu-state`：
  - `osu-state` 印出目前狀態。
  - `osu-state is-busy`：`playing` 或 `cooldown` 時 exit 0，其他 exit 1。
  - `osu-state wait-free [--timeout N]`：一直等到不忙才結束，給編譯前呼叫。超時 exit 124。
  - `osu-state status --json`、`osu-state check-config`、`osu-state claude-hook`（給 hook 用）。
- **背景服務**：一個常駐的 systemd user service，負責監聽事件並更新狀態檔。
  - 用事件驅動，不要每秒輪詢。
  - CPU 和記憶體都要小到可以忽略。

## 4. 指標（ii module）

- **類型**：Quickshell 狀態列的一個小元件，做成 IIMP module，照 `spec/SPEC-1.0.md`。
- **顯示規則**：
  - `off`：不顯示。
  - `idle`、`menu`：淡色圖示。
  - `playing`：醒目，例如亮色加一個小點。
  - `cooldown`：介於兩者之間，或沿用 `playing` 的樣式。
- **tooltip**：顯示狀態、持續了多久，有的話也顯示正在打的圖。
- **資料來源**：只讀狀態檔，不自己偵測。偵測集中在背景服務一處。
- **設定**：放 `~/.config/illogical-impulse/modules/<id>.json`。
  - 可以關掉 `idle` 和 `menu` 的顯示，只在打歌時出現。
  - `grace_secs` 也在這裡設。

## 5. 給 Claude 編譯用的保護

- 用 Claude Code 的全域 hook（PreToolUse，Bash）：
  - 指令裡有 `cargo`、`scripts/deploy-vps.sh` 這類重活時，先跑 `osu-state is-busy`。
  - 忙的話就擋下，回一句說明，例如「擁有者正在打 osu，晚點再編譯」。
- 不忙的時候，編譯也一律用低優先權跑：`nice -n 19`、`ionice -c3`。實作方式是 hook 回 `permissionDecision: allow` 加 `updatedInput` 改寫指令；`allow` 會略過該次權限詢問，`renice = false` 可關掉。
- `idle` 和 `menu` 不擋：只是開著或在選歌時可以編譯。
- 重活名單在 `~/.config/osu-state/config.toml` 的 `heavy_commands`，預設 `cargo`、`scripts/deploy-vps.sh`。

## 6. 驗收

- 開 osu 放背景 → `idle`，不擋編譯。
- 切回 osu 在選歌 → `menu`，不擋。
- 打一首歌 → `playing`，hook 擋下 cargo；暫停中也算 `playing`。
- 打完回到選歌 → `cooldown`，`grace_secs` 秒後變 `menu`。
- 關掉 osu → `off`。
- 背景服務重啟後，狀態能自己恢復正確。
- 狀態檔不存在時，hook 不能把所有編譯都擋死，要當成不忙。

## 7. 待確認

- ~~打歌時視窗標題會不會變~~：改用 log，不需要。
- ~~osu!lazer 的 RPC 文字~~：RPC 路徑走不通，不採用。
- ~~暫停（pause）~~：暫停不離開 Player 畫面，算 `playing`。2026-10-16 修正：暫停且 osu! 不在前景時算 `idle`（擁有者暫停後切回終端說「打完了」，hook 卻仍擋著）；切回前景或恢復時鐘即回 `playing`。
- `cooldown` 期間關掉 osu → 直接變 `off`（文件原本沒寫，已照此實作）。
- 第 4 節 ii module 的視覺樣式與設定鍵名，等實作時定。
- 多個 PreToolUse hook 同時回 `updatedInput` 的合併順序未實測（目前全域只有這一個 hook）。
