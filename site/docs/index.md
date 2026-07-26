# 什麼是 IIMP?

**IIMP(illogical-impulse Module Protocol)** 是給 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)「illogical-impulse」Quickshell 桌面的**嚴謹社群模塊協議**:讓愛好者可以安全地製作、分享、安裝彼此的 shell 模塊(bar 元件、懸浮視窗面板),帶完整的版本控制、相容性檢測、依賴管理與交易性安裝。

## 為什麼需要協議?

沒有協議之前,ii 桌面的社群模塊處境很糟:

- dots-hyprland 更新會 `rsync --delete` 整個 shell 樹——**手工安裝的模塊直接蒸發**。
- ii 本身沒有任何版本標記,模塊無從得知自己相容哪一版。
- 手工補丁彼此打架,裝了 A 再裝 B 常常兩個一起壞。

IIMP 用三個機制系統性解決:

| 機制 | 解決什麼 |
| --- | --- |
| **特徵探針(probe)** | ii 沒版本號,就直接驗證「檔案存在/包含字面字串」確認 API 表面相容 |
| **圍欄重組引擎** | 所有補丁包在圍欄註解內,每次從乾淨基底重算,安裝順序不影響結果 |
| **母本庫(store)** | 完整狀態存在 `~/.local/share/iimp/`(rsync 清除區之外),`iimod reapply` 隨時整批重建 |

## 兩種模塊

- **Tier A(插槽模塊)**——純資料夾,載入到 bar/window 插槽,零 stock 修改。壞掉最多該格空白,不影響桌面其他部分。
- **Tier B(補丁模塊)**——以結構化 insert-only 補丁修改 stock 檔。安裝時必須帶 `--allow-patches` 明確同意。

## 去中心化更新

沒有中央倉庫。每個 `.iimod` 內嵌自己的更新來源(一個靜態 `index.json`,掛在任何 HTTPS 位置),安裝後 `iimod update` 就能追新版。[ii.n1cat.xyz](https://ii.n1cat.xyz/) 的清單只負責索引,版本資訊永遠直接來自各模塊自己的來源。

## 從哪裡開始?

- 想**安裝模塊** → [安裝與快速開始](/guide/install)
- 想**自己寫一個** → [開發你的第一個模塊](/guide/develop)
- 想看**完整規格** → [SPEC-1.0.md](https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md)

::: warning 知情同意,不是沙箱
`capabilities` 宣告(exec/network/filesystem-write/dbus)由靜態 lint 交叉查核,但它提高的是誠實門檻,不是沙箱。安裝任何模塊前,請審查程式碼。詳見 [Capabilities 與安全](/reference/capabilities)。
:::
