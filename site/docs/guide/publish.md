---
description: 打包 .iimod、架設更新來源,並將模塊上架到 IIMP 模塊清單。
---

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

本 repo 內的模塊清單、雙語名稱/描述、Tier、capabilities、文件頁與 VitePress 導覽都由 `modules/<id>/module.json` 與 `README.md` 自動建立。上架時請送 PR 新增完整的 `modules/my_widget/` 目錄,不要手動編輯 `site/public/registry.json`。

最低要求:

- 目錄名必須等於 manifest 的 `id`
- `name` 與 `description` 必須同時提供 `zh_TW`、`en_US`
- 必須有 `README.md`;可另加 `README.en.md`,缺少時英文文件頁會明確標示並顯示繁中 README
- `tierB` 由非空 `patches` 自動推導,`capabilities` 與 `requires` 直接取自 manifest
- 提交前在 `site/` 執行 `npm run catalog:generate`,再跑 `npm run build`;過期的生成 catalog 會讓建置失敗

PR 合併後,首頁清單、雙語模塊文件頁與文件導覽會一起更新。下載按鈕只會在 release index 已包含相同版本的模塊時啟用。

## 用 GitHub Releases 託管(建議做法)

以本 repo 的參考模塊為例:tag 觸發的 release workflow 自動跑 `tools/release/build.sh`,產出 `.iimod`、`index.json` 與 `SHA256SUMS` 一起發佈到 GitHub Release,origin 自動指向 Releases 的 `latest/download` 位址。自己的模塊 repo 可以照抄這個模式:

```bash
git tag v0.1.0
git push origin v0.1.0
```
