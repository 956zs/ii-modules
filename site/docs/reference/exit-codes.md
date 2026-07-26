# Exit codes

`iimod` 的 exit code 是**穩定契約**(stable API),適合腳本化與問題回報。

| Exit code | 意義 |
| --- | --- |
| `0` | 成功 |
| `3` | 驗證失敗(manifest、佈局、capabilities lint) |
| `4` | 探針失敗(相容性不符,**絕對擋**) |
| `5` | 依賴或衝突 |
| `6` | 完整性(sha256 不符,檔案不落地) |
| `7` | 狀態錯誤 |
| `8` | 錨點失敗(Tier B 補丁定位不到) |
| `9` | Tier B 需要 `--allow-patches` |
| `10` | 協議版本不支援(`protocolVersion` 超出工具範圍) |

## 常見情境

- **exit 4**:dots-hyprland 改了模塊依賴的 API 表面。等模塊作者發相容新版,或回報 issue。
- **exit 6**:下載內容與 index.json 宣告的 sha256 不符——可能是來源被竄改或發佈失誤,**不要**繞過。
- **exit 9**:這是 Tier B 模塊,確認你理解它會修改 stock 檔後,加 `--allow-patches` 重跑。
