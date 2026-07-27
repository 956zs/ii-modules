import { defineConfig, type DefaultTheme, type HeadConfig } from 'vitepress'
import { loadModuleCatalog } from '../../scripts/module-catalog.mjs'

const modules = await loadModuleCatalog()
const firstModuleId = modules[0].id
const zhModuleItems: DefaultTheme.SidebarItem[] = modules.map((module) => ({
  text: module.name.zh_TW,
  link: `/modules/${module.id}`,
}))
const enModuleItems: DefaultTheme.SidebarItem[] = modules.map((module) => ({
  text: module.name.en_US,
  link: `/en/modules/${module.id}`,
}))

const SITE_ORIGIN = 'https://ii.n1cat.xyz'
const ZH_TITLE = 'IIMP 文件'
const ZH_DESCRIPTION =
  'IIMP——illogical-impulse 桌面的社群模塊協議。安裝、日常使用、模塊開發與發佈教學,以及完整協議參考。'
const EN_TITLE = 'IIMP Docs'
const EN_DESCRIPTION =
  'IIMP — the community module protocol for the illogical-impulse desktop. Install, daily usage, module development and publishing guides, plus the full protocol reference.'

const zhThemeConfig: DefaultTheme.Config = {
  siteTitle: ZH_TITLE,
  nav: [
    { text: '模塊清單', link: 'https://ii.n1cat.xyz/' },
    { text: '指南', link: '/guide/install', activeMatch: '^/guide/' },
    { text: '模塊', link: `/modules/${firstModuleId}`, activeMatch: '^/modules/' },
    { text: '參考', link: '/reference/concepts', activeMatch: '^/reference/' },
  ],
  sidebar: [
    {
      text: '入門',
      items: [
        { text: '什麼是 IIMP?', link: '/' },
        { text: '安裝與快速開始', link: '/guide/install' },
        { text: '日常使用與更新', link: '/guide/daily' },
      ],
    },
    {
      text: '模塊作者',
      items: [
        { text: '開發你的第一個模塊', link: '/guide/develop' },
        { text: '發佈與上架', link: '/guide/publish' },
      ],
    },
    {
      text: '模塊',
      items: zhModuleItems,
    },
    {
      text: '參考',
      items: [
        { text: '核心概念', link: '/reference/concepts' },
        { text: 'Capabilities 與安全', link: '/reference/capabilities' },
        { text: 'Exit codes', link: '/reference/exit-codes' },
        {
          text: 'SPEC-1.0(完整規格)',
          link: 'https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md',
        },
      ],
    },
  ],
  outline: { label: '本頁目錄', level: [2, 3] },
  docFooter: { prev: '上一頁', next: '下一頁' },
  returnToTopLabel: '回到頂部',
  sidebarMenuLabel: '選單',
  darkModeSwitchLabel: '外觀',
  langMenuLabel: '切換語言',
  editLink: {
    pattern: ({ filePath }) => {
      const dynamicModule = filePath.match(/^(?:en\/)?modules\/([^/]+)\.md$/)
      return dynamicModule
        ? `https://github.com/956zs/ii-modules/edit/main/modules/${dynamicModule[1]}/README.md`
        : `https://github.com/956zs/ii-modules/edit/main/site/docs/${filePath}`
    },
    text: '在 GitHub 上編輯此頁',
  },
}

const enThemeConfig: DefaultTheme.Config = {
  siteTitle: EN_TITLE,
  nav: [
    { text: 'Module Registry', link: 'https://ii.n1cat.xyz/' },
    { text: 'Guide', link: '/en/guide/install', activeMatch: '^/en/guide/' },
    { text: 'Modules', link: `/en/modules/${firstModuleId}`, activeMatch: '^/en/modules/' },
    { text: 'Reference', link: '/en/reference/concepts', activeMatch: '^/en/reference/' },
  ],
  sidebar: [
    {
      text: 'Getting Started',
      items: [
        { text: 'What is IIMP?', link: '/en/' },
        { text: 'Install & Quick Start', link: '/en/guide/install' },
        { text: 'Daily Usage & Updates', link: '/en/guide/daily' },
      ],
    },
    {
      text: 'Module Authors',
      items: [
        { text: 'Develop Your First Module', link: '/en/guide/develop' },
        { text: 'Publish & List', link: '/en/guide/publish' },
      ],
    },
    {
      text: 'Modules',
      items: enModuleItems,
    },
    {
      text: 'Reference',
      items: [
        { text: 'Core Concepts', link: '/en/reference/concepts' },
        { text: 'Capabilities & Security', link: '/en/reference/capabilities' },
        { text: 'Exit codes', link: '/en/reference/exit-codes' },
        {
          text: 'SPEC-1.0 (full spec)',
          link: 'https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md',
        },
      ],
    },
  ],
  editLink: {
    pattern: ({ filePath }) => {
      const dynamicModule = filePath.match(/^(?:en\/)?modules\/([^/]+)\.md$/)
      return dynamicModule
        ? `https://github.com/956zs/ii-modules/edit/main/modules/${dynamicModule[1]}/README.md`
        : `https://github.com/956zs/ii-modules/edit/main/site/docs/${filePath}`
    },
    text: 'Edit this page on GitHub',
  },
}

export default defineConfig({
  base: '/docs/',
  outDir: '../dist/docs',
  cleanUrls: true,
  appearance: 'force-dark',

  locales: {
    root: {
      label: '繁體中文',
      lang: 'zh-Hant-TW',
      title: ZH_TITLE,
      description: ZH_DESCRIPTION,
      themeConfig: zhThemeConfig,
    },
    en: {
      label: 'English',
      lang: 'en-US',
      title: EN_TITLE,
      description: EN_DESCRIPTION,
      themeConfig: enThemeConfig,
    },
  },

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['meta', { name: 'theme-color', content: '#a78bfa' }],
    // Open Graph（Discord/Telegram/FB 共用;爬蟲不跑 JS,必須是靜態標籤）。
    // og:title / og:description / og:url / og:locale 逐頁由 transformHead 生成。
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: 'IIMP' }],
    ['meta', { property: 'og:image', content: `${SITE_ORIGIN}/og.png` }],
    ['meta', { property: 'og:image:width', content: '1200' }],
    ['meta', { property: 'og:image:height', content: '630' }],
    ['meta', { property: 'og:image:alt', content: 'IIMP — 給 illogical-impulse 桌面的社群模塊協議' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:image', content: `${SITE_ORIGIN}/og.png` }],
  ],
  transformHead({ pageData }): HeadConfig[] {
    const isEn = pageData.relativePath.startsWith('en/')
    const siteTitle = isEn ? EN_TITLE : ZH_TITLE
    // 對齊 VitePress 渲染的 <title>（`:title | <site title>`)。
    const title = pageData.title ? `${pageData.title} | ${siteTitle}` : siteTitle
    const description = pageData.description || (isEn ? EN_DESCRIPTION : ZH_DESCRIPTION)
    // cleanUrls: guide/install.md → /docs/guide/install;en/index.md → /docs/en/。
    const path = pageData.relativePath.replace(/index\.md$/, '').replace(/\.md$/, '')
    return [
      ['meta', { property: 'og:title', content: title }],
      ['meta', { property: 'og:description', content: description }],
      ['meta', { property: 'og:url', content: `${SITE_ORIGIN}/docs/${path}` }],
      ['meta', { property: 'og:locale', content: isEn ? 'en_US' : 'zh_TW' }],
      ['meta', { name: 'twitter:title', content: title }],
      ['meta', { name: 'twitter:description', content: description }],
    ]
  },

  themeConfig: {
    socialLinks: [{ icon: 'github', link: 'https://github.com/956zs/ii-modules' }],
    search: {
      provider: 'local',
      options: {
        locales: {
          // English UI is the built-in default; only the root (zh) needs strings.
          root: {
            translations: {
              button: { buttonText: '搜尋文件', buttonAriaLabel: '搜尋文件' },
              modal: {
                displayDetails: '顯示詳細內容',
                resetButtonTitle: '清除搜尋',
                backButtonTitle: '關閉搜尋',
                noResultsText: '找不到結果',
                footer: {
                  selectText: '選取',
                  navigateText: '切換',
                  closeText: '關閉',
                },
              },
            },
          },
        },
      },
    },
  },
})
