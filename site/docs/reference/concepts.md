# 核心概念

一頁看懂 IIMP 的名詞。深入細節請讀 [SPEC-1.0.md](https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md)。

## Tier A:插槽模塊

純資料夾,載入到 **bar** 或 **window** 插槽,**零 stock 修改**。模塊壞掉最多是該格空白,桌面其他部分不受影響。payload 樹就是安裝後的樹,裝在 `$II/mod/<id>/`。

## Tier B:補丁模塊

以**結構化 insert-only 補丁**修改 stock 檔。manifest 的 `patches` 非空即為 Tier B;安裝與每次更新都需要 `--allow-patches` 明確同意。

## 探針(probe)

ii 沒有版本號,IIMP 不猜版本——直接驗證 API 表面:

- `file_exists`:某個 stock 檔存在
- `file_contains`:某個 stock 檔包含字面字串

探針失敗是**絕對擋**(exit 4):stock 的 API 表面變了,模塊不該裝上去。基準線(`qs.modules.common` 等)免探針;其他一切 stock 依賴都必須宣告。

## 圍欄重組引擎

所有 Tier B 補丁都包在圍欄註解內:

```
// >>> iimp <module-id>/<n> >>>
…插入的內容…
// <<< iimp <module-id>/<n> <<<
```

每次任何模塊安裝/移除,引擎**從乾淨基底重算全部補丁**——所以安裝順序不影響結果,補丁之間不會互相打架,移除一個模塊也不會留下殘渣。

## 母本庫(store)

完整安裝狀態(模塊 payload、乾淨 stock 基底、registry)存在 `~/.local/share/iimp/`——在 dots-hyprland `rsync --delete` 的清除範圍**之外**。`iimod reapply` 隨時可以從母本庫整批重建 shell 樹裡的一切。

## 聯邦式更新(origin)

沒有中央倉庫。每個模塊記住自己的更新來源(一個靜態 `index.json`,任何 HTTPS 位置)。`iimod update` 逐模塊查各自的來源;下載一律核對 sha256。[模塊清單網站](https://ii.n1cat.xyz/)只是索引,版本資訊直接來自各模塊的 origin。

## Capabilities

模塊必須誠實宣告程式碼實際做的事:`exec` / `network` / `filesystem-write` / `dbus`。靜態 lint 交叉查核,用了沒宣告直接拒裝。詳見 [Capabilities 與安全](/reference/capabilities)。
