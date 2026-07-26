import { defineConfig, type HeadConfig } from 'vitepress'

const SITE_ORIGIN = 'https://ii.n1cat.xyz'
const DOCS_DESCRIPTION =
  'IIMP——illogical-impulse 桌面的社群模塊協議。安裝、日常使用、模塊開發與發佈教學,以及完整協議參考。'

export default defineConfig({
  lang: 'zh-Hant-TW',
  title: 'IIMP 文件',
  description: DOCS_DESCRIPTION,
  base: '/docs/',
  outDir: '../dist/docs',
  cleanUrls: true,
  appearance: 'force-dark',
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['meta', { name: 'theme-color', content: '#a78bfa' }],
    // Open Graph（Discord/Telegram/FB 共用;爬蟲不跑 JS,必須是靜態標籤）。
    // og:title / og:description / og:url 逐頁由 transformHead 生成。
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: 'IIMP' }],
    ['meta', { property: 'og:image', content: `${SITE_ORIGIN}/og.png` }],
    ['meta', { property: 'og:image:width', content: '1200' }],
    ['meta', { property: 'og:image:height', content: '630' }],
    ['meta', { property: 'og:image:alt', content: 'IIMP — 給 illogical-impulse 桌面的社群模塊協議' }],
    ['meta', { property: 'og:locale', content: 'zh_TW' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:image', content: `${SITE_ORIGIN}/og.png` }],
  ],
  transformHead({ pageData }): HeadConfig[] {
    // 對齊 VitePress 渲染的 <title>（`:title | IIMP 文件`）。
    const title = pageData.title ? `${pageData.title} | IIMP 文件` : 'IIMP 文件'
    const description = pageData.description || DOCS_DESCRIPTION
    // cleanUrls: guide/install.md → /docs/guide/install;index.md → /docs/。
    const path = pageData.relativePath.replace(/(?:^|\/)index\.md$/, '').replace(/\.md$/, '')
    return [
      ['meta', { property: 'og:title', content: title }],
      ['meta', { property: 'og:description', content: description }],
      ['meta', { property: 'og:url', content: `${SITE_ORIGIN}/docs/${path}` }],
      ['meta', { name: 'twitter:title', content: title }],
      ['meta', { name: 'twitter:description', content: description }],
    ]
  },
  themeConfig: {
    siteTitle: 'IIMP 文件',
    nav: [
      { text: '指南', link: '/guide/install', activeMatch: '^/guide/' },
      { text: '參考', link: '/reference/concepts', activeMatch: '^/reference/' },
      { text: '模塊清單', link: 'https://ii.n1cat.xyz/' },
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
    socialLinks: [{ icon: 'github', link: 'https://github.com/956zs/ii-modules' }],
    outline: { label: '本頁目錄', level: [2, 3] },
    docFooter: { prev: '上一頁', next: '下一頁' },
    returnToTopLabel: '回到頂部',
    sidebarMenuLabel: '選單',
    darkModeSwitchLabel: '外觀',
    editLink: {
      pattern: 'https://github.com/956zs/ii-modules/edit/main/site/docs/:path',
      text: '在 GitHub 上編輯此頁',
    },
    search: {
      provider: 'local',
      options: {
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
})
