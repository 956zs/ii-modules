---
description: 從零開始:安裝 iimod CLI,然後裝上你的第一個 IIMP 模塊。
---

# 安裝與快速開始

本頁帶你從零開始:裝好 `iimod` CLI,然後安裝第一個模塊。

## 前置需求

- 已安裝 [dots-hyprland](https://github.com/end-4/dots-hyprland) 的 **illogical-impulse** Quickshell 桌面
- Linux x86_64(其他架構請走[從原始碼建置](#從原始碼建置))

## 安裝 iimod CLI

透過網站提供的第一方安裝腳本，從穩定下載端點取得官方 binary 並核對 SHA256：

```bash
sh -c "$(curl -sS https://ii.n1cat.xyz/install-iimod.sh)"
```

腳本會先說明將安裝的內容、目標 `/usr/local/bin/iimod`、SHA256 驗證狀態，以及何時可能出現 `sudo` 密碼提示。binary 只會下載至受限的暫存目錄；checksum 不合法或不相符時會立即停止，不會執行 `sudo`，暫存檔也會自動清除。

這個短指令會直接執行目前由網站透過 HTTPS 提供的腳本，因此信任邊界包含 `ii.n1cat.xyz` 與 TLS。若要先審查再執行，請開啟 [install-iimod.sh](https://ii.n1cat.xyz/install-iimod.sh)，或先下載到本機閱讀後執行。下載的 binary 不會直接 pipe 給 `sudo`；腳本會先完成 SHA256 驗證，再單獨呼叫 `sudo install`。

::: tip 穩定端點
網站會從最高版本的 `iimod/v<version>` Release 投影 binary 與 `.sha256`。CLI 與各模塊獨立發版，不依賴 repository-wide Latest Release。
:::

### 從原始碼建置

```bash
git clone https://github.com/956zs/ii-modules
cd ii-modules
cargo build --release --manifest-path tools/iimod/Cargo.toml
install -Dm755 tools/iimod/target/release/iimod ~/.local/bin/iimod
```

## 安裝第一個模塊

安裝指令會使用網站聚合索引中該版本的不可變 GitHub Release 資產 URL，例如：

```bash
iimod install https://github.com/956zs/ii-modules/releases/download/module%2Fnetwork_traffic%2Fv1.5.0/network_traffic-1.5.0.iimod
```

`iimod install` 是**交易性**的:安裝過程中任何一步失敗(探針不符、雜湊不符、錨點失敗……)都會自動回滾,桌面不會處於半壞狀態。

從 URL 安裝時,iimod 會自動記錄模塊的更新來源(origin),之後 `iimod update` 就能追新版——詳見[日常使用與更新](/guide/daily)。

### 安裝本機模塊目錄

開發或手動下載時,也可以指向一個模塊資料夾,建議先跑驗證:

```bash
iimod validate  my_module/   # 驗證 manifest、佈局、權限 lint
iimod check     my_module/   # 相容性探針＋依賴＋錨點乾跑
iimod install   my_module/   # 交易性安裝
```

### Tier B 模塊

會修改 stock 檔的模塊(清單上標 **Tier B**)必須明確同意才能安裝:

```bash
iimod install some_patch_module/ --allow-patches
```

::: warning
Tier B 模塊的**每次更新**也都要重新 `--allow-patches`——新版的補丁內容可能不同。
:::

## 開關模塊

安裝後,ii 的設定 app(<kbd>Ctrl</kbd>+<kbd>Super</kbd>+<kbd>,</kbd>)會多出 **Modules** 頁:開關各模塊、調整各模塊自己的設定。

CLI 也可以:

```bash
iimod list              # 列出已安裝模塊與狀態
iimod enable  <id>
iimod disable <id>
```

## dots-hyprland 更新之後 {#reapply}

dots-hyprland 更新會 `rsync --delete` 整個 shell 樹,把已安裝模塊一併清掉。**更新後必跑**:

```bash
iimod reapply
```

完整狀態存在 `~/.local/share/iimp/`(rsync 清除區之外),`reapply` 一鍵把所有模塊、補丁重新套回。
