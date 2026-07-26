---
description: capabilities 欄位的四種能力宣告、lint 偵測方式,與安裝時的安全提示。
---

# Capabilities 與安全

`capabilities` 是 manifest 的必要欄位(可以是 `[]`),**誠實宣告模塊的程式碼實際做什麼**。

## 四種 capability

| Capability | 意義 | Lint 偵測(啟發式) |
| --- | --- | --- |
| `exec` | 會執行外部程式 | `Process {`、`execDetached(`、`Hyprland.dispatch(` |
| `network` | 會進行網路 I/O | `XMLHttpRequest`、`WebSocket`、`Socket` |
| `filesystem-write` | 會寫入自身設定以外的檔案 | `.setText(`、`writeAdapter(`(合法的 ConfigLoader 模式除外) |
| `dbus` | 會存取 D-Bus | `DBus` |

## Lint 裁決

- **用了但沒宣告 → 驗證失敗(exit 3),拒裝**
- 宣告了但沒偵測到 → 只給警告(過度宣告永遠允許)
- 唯讀檔案(FileView 不寫入)不需要任何 capability

## 這不是沙箱

::: danger 知情同意 ≠ 隔離
lint 是 grep 等級的啟發式,規格文件也如此明載。它提高的是**誠實門檻**——讓宣告與程式碼對得上——不是執行期隔離。模塊裝進你的 shell 之後,擁有和 shell 相同的權限。

**安裝任何模塊前,請審查程式碼。** Tier B 模塊(會改 stock 檔)尤其如此,所以每次安裝與更新都強制 `--allow-patches` 重新同意。
:::

## 對模塊作者的建議

- 用 `iimod suggest` 自動推導宣告,再人工確認
- 寧可過度宣告,不要漏宣告
- README 裡說明每個 capability 的用途(例如「exec:呼叫 `nethogs` 取得 per-app 流量」),幫使用者做知情決定
