# 開發你的第一個模塊

這一頁帶你從腳手架到能安裝的模塊。完整規範請以 [SPEC-1.0.md](https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md) 為準。

## 建立腳手架

```bash
iimod init my_widget
```

產出的目錄結構(payload 樹**就是**安裝後的樹,沒有目的地映射):

```
my_widget/
  module.json                 # manifest — 必要
  bar.qml                     # bar 插槽入口(slots 含 "bar" 時)
  main.qml                    # window 插槽入口(slots 含 "window" 時)
  settings.qml                # 選用:設定片段(Item 根)
  ConfigLoader.qml            # 腳手架附的設定持久化範本
  translations/<locale>.json  # 選用:扁平 key→string 字典
  README.md                   # 建議
```

## QML 規則(重要)

這些規則由 `iimod validate` 強制,違反會直接拒絕:

- `bar.qml` 的根**必須是視覺 Item**(由 QtQuick `Loader` 載入)。
- `main.qml` 的根**必須是 `Scope`、`PanelWindow` 或 `LazyLoader`**(經 `Qt.createComponent` 實例化,自己管理視窗)。
- `.qml` 檔名**不得**與 `$II/services/` 或 `$II/modules/common/**` 下任何檔案同名(QML 同目錄型別解析會遮蔽 stock singleton)。
- 模塊內**禁用 `pragma Singleton`**;在入口元件實例化一個普通邏輯物件往下傳。
- 引用自己目錄的同層元件時,必須明確 `import qs.mod.<own-id>`(路徑載入的檔案沒有隱式同目錄解析)。**禁止 import 其他模塊的目錄**。

### 設定持久化

不要寫 `~/.config/illogical-impulse/config.json`(shell 的 JsonAdapter 會抹掉未宣告的 key)。模塊自己的選項存 `~/.config/illogical-impulse/modules/<id>.json`,用腳手架附的 `ConfigLoader.qml`(FileView + JsonAdapter,watchChanges + debounced write)。

## 探針與 capabilities

ii 沒有版本號,相容性靠**探針**:宣告你依賴的 stock 檔案存在、或包含某段字面字串。基準線(`qs.modules.common` 的 `Config`/`Appearance`/`Directories`、widgets、functions、`qs.services.Translation`)免探針,**其他一切 stock 型別都必須有探針覆蓋**。

`capabilities` 是誠實宣告:`exec` / `network` / `filesystem-write` / `dbus`,靜態 lint 交叉查核——用了沒宣告,驗證直接失敗(exit 3)。

兩者都可以先讓工具推導:

```bash
iimod suggest my_widget/    # 自動建議 probes 與 capabilities
```

## 開發迴圈

```bash
iimod validate my_widget/   # manifest、佈局、lint
iimod check    my_widget/   # 探針＋依賴＋錨點乾跑
iimod install  my_widget/   # 裝上實機看效果(交易性,壞了自動回滾)
```

版本號用嚴格 semver(`X.Y.Z[-pre]`)。改了什麼就 bump 什麼:修 bug 動 patch,加功能動 minor,破壞相容動 major。

## 參考實作

- [`modules/network_traffic/`](https://github.com/956zs/ii-modules/tree/main/modules/network_traffic) — 完整功能的 bar 模塊,含逐檔說明
- [`examples/hello_window/`](https://github.com/956zs/ii-modules/tree/main/examples/hello_window) — 最小視窗範例

::: tip 用 AI agent 開發?
repo 的 `.claude/skills/` 附兩個 project skills(`ii-module-author`、`ii-module-manage`),讓 Claude Code 在這個專案裡自動遵守協議紀律。
:::

寫完之後,下一步:[發佈與上架](/guide/publish)。
