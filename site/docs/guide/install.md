# 安裝與快速開始

本頁帶你從零開始:裝好 `iimod` CLI,然後安裝第一個模塊。

## 前置需求

- 已安裝 [dots-hyprland](https://github.com/end-4/dots-hyprland) 的 **illogical-impulse** Quickshell 桌面
- Linux x86_64(其他架構請走[從原始碼建置](#從原始碼建置))

## 安裝 iimod CLI

從 GitHub Releases 下載官方 binary:

```bash
curl -fsSL -o iimod https://github.com/956zs/ii-modules/releases/latest/download/iimod-linux-x86_64 && chmod +x iimod && sudo install iimod /usr/local/bin/iimod
```

::: tip 核對 sha256
每個 Release 都附 `SHA256SUMS`。下載後可用 `sha256sum -c` 核對,確認 binary 未被竄改。
:::

### 從原始碼建置

```bash
git clone https://github.com/956zs/ii-modules
cd ii-modules
cargo build --release --manifest-path tools/iimod/Cargo.toml
install -Dm755 tools/iimod/target/release/iimod ~/.local/bin/iimod
```

## 安裝第一個模塊

從 [模塊清單](https://ii.n1cat.xyz/) 找到想裝的模塊,點開卡片複製安裝指令,例如:

```bash
iimod install https://github.com/956zs/ii-modules/releases/latest/download/network_traffic-1.4.0.iimod
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
