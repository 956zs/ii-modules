# indicator_tools — 右鍵指示器開工具（Tier B）

還原自社群補丁：右鍵 bar 上的 WiFi／藍牙指示圖示，直接啟動**後端原生**的
D-Bus 圖形工具。左鍵（開側欄）行為完全不變；水平與垂直 bar 都生效。

**起源**：dots-hyprland 的 shell 以 `nmcli`／NetworkManager profile 管理 WiFi；
跑 **iwd 後端**的人，已知網路存在 `/var/lib/iwd/`，與 NM 存儲互不相通，側欄
WiFi 功能因此半殘。原補丁的解法＝繞過 shell UI，右鍵直開各後端自己的 D-Bus 客戶端。

| 圖示右鍵 | 啟動（備援鏈，取第一個存在的） |
|---|---|
| WiFi | `iwgtk`（iwd）→ `nm-connection-editor`（NM）→ `better-control --wifi` |
| 藍牙 | `overskride`（BlueZ 直連）→ `blueberry` → `blueman-manager` |

iwd 環境命中前者、NM 環境自動落到後者——同一個模塊兩種棧都正確。

## 安裝

```bash
iimod validate modules/indicator_tools/
iimod check    modules/indicator_tools/
iimod install  modules/indicator_tools/ --allow-patches   # Tier B 需明確同意
```

## 實作說明

四個 insert-only 補丁（水平/垂直 bar × WiFi/藍牙），各在 stock 的
MaterialSymbol 圖示內插入一個只收右鍵的 `MouseArea`（`anchors.fill`），
`Quickshell.execDetached` 跑 sh 備援鏈。左鍵不在 acceptedButtons 內，
事件照常落到 stock 的側欄按鈕。無 payload UI（window slot 空 Scope）。

想換工具：fork 後改 `module.json` 裡兩個 `content` 的指令鏈即可。
