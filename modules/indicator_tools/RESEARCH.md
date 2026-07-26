# 封存：朋友的「現成工具」搜索結果（2026-07-27）

此工作線已擱置，待重寫。兩路並行搜索的結論歸檔於此。

## 指紋
現成、圓角漂亮 UI、多網卡各自獨立分區、識別藍牙網路共享（PAN）、
D-Bus、為繞開 iwd 後端 vs dots-hyprland nmcli 存儲衝突而裝、非 cmst。

## 兩路搜索的首選（意見分歧，皆未獲直接引文證實）

1. **iwgtk（WiFi）＋ Overskride（藍牙）** — 網路掃描路線的首選。
   iwgtk 是 Hyprland 官方 wiki 對 iwd 場景的指名推薦、直連 iwd D-Bus
   完全繞開 NM（正面解決存儲衝突）、GTK4；Overskride 確認 GTK4+libadwaita
   圓角、多介面卡支援。弱點：Overskride **無 PAN**（README 證實）——
   「藍牙連的 WiFi」可能其實是 bar/NM 層的表現而非工具內功能。
2. **gnome-control-center 的 wifi + bluetooth 兩個面板** — iwd/社群角度
   路線的首選。唯一每項指紋都有文件直證的候選（2017 重設計明文支援
   多 WiFi 網卡分區、Network 面板原生顯示 BT tethering、libadwaita
   圓角、`gnome-control-center wifi` / `bluetooth` 正好是「兩個」可獨立
   啟動的面板、dots 的 settings 備援鏈本來就含它）。弱點：重量級依賴，
   與「輕量 rice」氣質不合。

已排除：cmst（使用者證實不是）、Overskride-as-PAN、Deepin 控制中心
（維護者證實無 PAN）。

## 重寫時可撿的既有資產
- `NetworksLogic.qml`：nmcli -t 解析器（跳脫冒號、多網卡、BT 型連線、
  SSID 去重取最強訊號）——資料層可直接復用
- `PanelShell.qml`：四種 bar 位置錨定＋focus grab＋Esc 的窗框
- 補丁＋IPC 橋（右鍵 → 模塊面板）架構
