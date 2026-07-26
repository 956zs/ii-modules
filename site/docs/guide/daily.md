# 日常使用與更新

裝好模塊之後,平常會用到的指令都在這裡。

## 常用指令

```bash
iimod list              # 已安裝模塊、版本與狀態
iimod info <id>         # 單一模塊詳細資訊
iimod enable <id>       # 啟用
iimod disable <id>      # 停用(不解除安裝)
iimod verify            # 核對安裝狀態與檔案完整性
iimod remove <id>       # 解除安裝
```

## 更新模塊

IIMP 的更新是**聯邦式**的:沒有中央倉庫,每個模塊在安裝時記住自己的來源(origin)。

```bash
iimod update --dry-run   # 只查有什麼新版,不動任何東西
iimod update             # 全部更新
```

更新走與安裝相同的交易性管線:

- 下載一律核對 `sha256`,不符即 exit `6`,檔案不落地
- 失敗自動回滾,模塊設定保留,origin 延續
- **Tier B 模塊**的更新需要重新 `--allow-patches`(新版補丁可能不同)

### origin 是怎麼決定的?

來源是一個靜態 `index.json`,掛在任何 HTTPS 位置(GitHub Releases、raw、自架都可以)。優先序:

1. `--origin <url>` flag(永遠可顯式覆寫)
2. `.iimod` 內嵌的 origin(正式發佈的包都內嵌,`pack --origin` 產生)
3. 從 URL 安裝時,自動記同目錄的 `index.json`

傳輸使用系統 `curl`,僅允許 `https://` 與 `file://`(後者供區網分享與離線測試)。

## dots-hyprland 更新後:reapply

::: danger 必跑
dots-hyprland 更新會 `rsync --delete` 整個 shell 樹。更新完桌面後,執行:

```bash
iimod reapply
```

所有模塊與補丁會從母本庫(`~/.local/share/iimp/`)整批重建。
:::

## 出錯時

`iimod` 的 exit code 是穩定契約,每個代碼有固定意義(探針失敗、依賴衝突、完整性不符……),方便腳本化與回報問題。完整對照見 [Exit codes](/reference/exit-codes)。
