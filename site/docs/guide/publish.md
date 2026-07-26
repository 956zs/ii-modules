# 發佈與上架

模塊寫好、`validate`/`check` 都過了,接下來讓別人裝得到、更新得到。

## 打包 `.iimod`

```bash
iimod pack my_widget/ --origin https://example.com/mods/index.json
```

產出 `my_widget-0.1.0.iimod`(zip 格式,含 `integrity.json`:manifest 與每個檔案的 sha256)。

::: warning pack 強制要求 origin
`iimod pack` 必須帶 `--origin <index.json 網址>`(內嵌更新來源,拿到檔案就能裝、裝了就能更新),或明確帶 `--no-origin` 退出(僅供本機/開發用途)。兩個 flag 都沒帶會直接拒絕打包。
:::

## 架設更新來源(index.json)

來源就是一個靜態 JSON,掛在任何 HTTPS 位置——GitHub Releases、GitHub raw、自架伺服器都可以:

```json
{
  "indexVersion": 1,
  "modules": {
    "my_widget": {
      "version": "0.1.0",
      "url": "my_widget-0.1.0.iimod",
      "sha256": "…"
    }
  }
}
```

- `url` 可以相對於 index.json 的位置
- `sha256` 必填——下載端一律核對,不符即拒裝
- 發新版 = 上傳新 `.iimod` + 改 index.json 的 `version`/`url`/`sha256`

使用者這端什麼都不用做,`iimod update` 自然看得到新版。

## 上架到模塊清單(ii.n1cat.xyz)

清單是聯邦式索引:**送一個 PR** 到 [`site/public/registry.json`](https://github.com/956zs/ii-modules/edit/main/site/public/registry.json),加一筆:

```json
{
  "id": "my_widget",
  "name": { "en_US": "My Widget", "zh_TW": "我的小工具" },
  "description": {
    "zh_TW": "一句話說明模塊做什麼。",
    "en_US": "One-line description."
  },
  "tierB": false,
  "capabilities": ["exec"],
  "origin": "https://example.com/mods/index.json",
  "repo": "https://github.com/you/my_widget"
}
```

- `origin` 指向你的 index.json——清單網站直接從這裡讀**即時版本**,你發新版不用再改 registry
- `tierB` 與 `capabilities` 必須誠實填寫,與 manifest 一致
- PR 合併後,模塊立即出現在清單上

## 用 GitHub Releases 託管(建議做法)

以本 repo 的參考模塊為例:tag 觸發的 release workflow 自動跑 `tools/release/build.sh`,產出 `.iimod`、`index.json` 與 `SHA256SUMS` 一起發佈到 GitHub Release,origin 自動指向 Releases 的 `latest/download` 位址。自己的模塊 repo 可以照抄這個模式:

```bash
git tag v0.1.0
git push origin v0.1.0
```
