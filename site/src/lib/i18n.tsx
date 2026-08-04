import { createContext, useContext, useEffect, useState } from 'react'

/** Locale keys deliberately match the registry's name/description keys. */
export type Locale = 'zh_TW' | 'en_US'

const STORAGE_KEY = 'iimp-locale'

const zh_TW = {
  htmlLang: 'zh-Hant',
  pageTitle: 'IIMP · illogical-impulse 模塊清單',
  // Header / footer
  docs: '文件',
  modules: '模塊',
  menu: '選單',
  closeMenu: '關閉選單',
  githubRepo: 'GitHub Repo',
  switchLanguage: 'Switch to English',
  languageToggleLabel: 'EN',
  footerTagline: '聯邦式模塊清單——每個模塊自帶更新來源，清單只負責索引。',
  addModule: '新增模塊',
  siteLinks: '網站連結',
  // Hero
  heroTitleTop: '給 illogical-impulse 桌面的',
  heroTitleBrand: '社群模塊協議',
  heroTagline:
    'IIMP 讓 Quickshell 模塊像套件一樣安裝、更新與分享——每個模塊自帶更新來源， 清單只負責索引，版本永遠即時。',
  quickInstall: '快速安裝',
  stepInstallCli: '安裝 iimod CLI（來自 GitHub Releases）',
  stepInstallModule: '安裝模塊',
  stepInstallModuleExample: (name: string) => `安裝模塊——例如「${name}」`,
  registryFailedHero: '模塊清單暫時無法取得，請稍後再試。',
  pickFromList: '從下方清單挑選模塊，複製對應的安裝指令。',
  readDocs: '閱讀完整教學與文件',
  // Copy
  copy: '複製',
  copied: '已複製',
  copyCommand: '複製指令',
  copySha256: '複製 sha256',
  // Module card / dialog
  versionUnknown: '版本未知',
  waitingForRelease: '等待發佈',
  waitingForReleaseDetail: (source: string, released: string) =>
    `原始碼版本 ${source} 尚未發佈（最新 release：${released}），下載暫停。`,
  moduleDocs: '模塊文件',
  viewDetails: (name: string) => `查看「${name}」詳細資訊`,
  tierBWarning: '此模塊會修改 stock 檔，安裝前請詳閱說明',
  tierBInline: '會修改 stock 檔，安裝前請詳閱說明',
  tierBBadge: '修改 stock 檔',
  capabilitiesTitle: '權限與能力',
  capabilityInfo: {
    exec: '會執行外部程式',
    network: '會進行網路連線',
    'filesystem-write': '會寫入自身設定以外的檔案',
    dbus: '會存取 D-Bus 系統服務',
  } as Record<string, string>,
  capabilityUnknown: '未知能力',
  noCapabilities: '不需要任何特殊能力。',
  versionInstallTitle: '版本與安裝',
  versionUnavailable: '版本資訊暫時無法取得，請稍後再試。',
  versionUnavailableShort: '版本資訊暫時無法取得',
  download: '下載 .iimod',
  repo: 'Repo',
  // Module grid
  moduleList: '模塊清單',
  moduleCount: (n: number) => `${n} 個模塊`,
  searchPlaceholder: '搜尋模塊名稱或描述…',
  searchModules: '搜尋模塊',
  clearSearch: '清除搜尋',
  searchResult: (n: number, q: string) => `找到 ${n} 個符合「${q}」的模塊`,
  noMatchTitle: '找不到符合的模塊',
  noMatchDescription: (q: string) => `沒有模塊符合「${q}」，換個關鍵字試試。`,
  publishTitle: '發佈你的模塊',
  publishDescription: '新增 modules/<id> 並送出 PR，清單與文件會自動建立',
  // App-level error
  registryErrorTitle: '模塊清單暫時無法取得',
  registryErrorDescription: '網路或伺服器出了點狀況，請稍後再試。',
  reload: '重新載入',
}

const en_US: Strings = {
  htmlLang: 'en',
  pageTitle: 'IIMP · illogical-impulse Module Registry',
  docs: 'Docs',
  modules: 'Modules',
  menu: 'Menu',
  closeMenu: 'Close menu',
  githubRepo: 'GitHub Repo',
  switchLanguage: '切換為繁體中文',
  languageToggleLabel: '中文',
  footerTagline:
    'A federated module registry — every module carries its own update source; the list only indexes.',
  addModule: 'Add module',
  siteLinks: 'Site links',
  heroTitleTop: 'A community module protocol',
  heroTitleBrand: 'for the illogical-impulse desktop',
  heroTagline:
    'IIMP lets Quickshell modules install, update, and share like packages — every module carries its own update source; the registry only indexes, so versions are always live.',
  quickInstall: 'Quick install',
  stepInstallCli: 'Install the iimod CLI (from GitHub Releases)',
  stepInstallModule: 'Install a module',
  stepInstallModuleExample: (name: string) => `Install a module — e.g. “${name}”`,
  registryFailedHero: 'The module registry is temporarily unavailable — please try again later.',
  pickFromList: 'Pick a module from the list below and copy its install command.',
  readDocs: 'Read the full guide and docs',
  copy: 'Copy',
  copied: 'Copied',
  copyCommand: 'Copy command',
  copySha256: 'Copy sha256',
  versionUnknown: 'Version unknown',
  waitingForRelease: 'Waiting for release',
  waitingForReleaseDetail: (source: string, released: string) =>
    `Source version ${source} is not released yet (latest release: ${released}); download is disabled.`,
  moduleDocs: 'Module docs',
  viewDetails: (name: string) => `View details for “${name}”`,
  tierBWarning: 'This module modifies stock files — read the notes before installing',
  tierBInline: 'Modifies stock files — read the notes before installing',
  tierBBadge: 'Modifies stock files',
  capabilitiesTitle: 'Permissions & capabilities',
  capabilityInfo: {
    exec: 'Executes external programs',
    network: 'Makes network connections',
    'filesystem-write': 'Writes files outside its own config',
    dbus: 'Accesses D-Bus system services',
  },
  capabilityUnknown: 'Unknown capability',
  noCapabilities: 'Requires no special capabilities.',
  versionInstallTitle: 'Version & install',
  versionUnavailable: 'Version info is temporarily unavailable — please try again later.',
  versionUnavailableShort: 'Version info temporarily unavailable',
  download: 'Download .iimod',
  repo: 'Repo',
  moduleList: 'Module registry',
  moduleCount: (n: number) => (n === 1 ? '1 module' : `${n} modules`),
  searchPlaceholder: 'Search modules by name or description…',
  searchModules: 'Search modules',
  clearSearch: 'Clear search',
  searchResult: (n: number, q: string) =>
    `${n} ${n === 1 ? 'module' : 'modules'} matching “${q}”`,
  noMatchTitle: 'No matching modules',
  noMatchDescription: (q: string) => `Nothing matches “${q}” — try a different keyword.`,
  publishTitle: 'Publish your module',
  publishDescription: 'Add modules/<id> in a PR; the catalog and docs are generated automatically',
  registryErrorTitle: 'Module registry unavailable',
  registryErrorDescription: 'A network or server hiccup — please try again later.',
  reload: 'Reload',
}

export type Strings = typeof zh_TW

const dictionaries: Record<Locale, Strings> = { zh_TW, en_US }

/** Docs live at /docs/ (zh root) and /docs/en/ (English locale). */
export function docsUrl(locale: Locale): string {
  return locale === 'en_US' ? '/docs/en/' : '/docs/'
}

function detectLocale(): Locale {
  const stored = localStorage.getItem(STORAGE_KEY)
  if (stored === 'zh_TW' || stored === 'en_US') return stored
  return navigator.language.toLowerCase().startsWith('zh') ? 'zh_TW' : 'en_US'
}

interface I18nContextValue {
  locale: Locale
  t: Strings
  toggleLocale: () => void
}

const I18nContext = createContext<I18nContextValue | null>(null)

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocale] = useState<Locale>(detectLocale)

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, locale)
    document.documentElement.lang = dictionaries[locale].htmlLang
    document.title = dictionaries[locale].pageTitle
  }, [locale])

  return (
    <I18nContext.Provider
      value={{
        locale,
        t: dictionaries[locale],
        toggleLocale: () => setLocale((prev) => (prev === 'zh_TW' ? 'en_US' : 'zh_TW')),
      }}
    >
      {children}
    </I18nContext.Provider>
  )
}

export function useI18n(): I18nContextValue {
  const ctx = useContext(I18nContext)
  if (!ctx) throw new Error('useI18n must be used within I18nProvider')
  return ctx
}
