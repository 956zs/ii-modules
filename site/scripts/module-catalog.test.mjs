import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import {
  documentationEditUrl,
  loadModuleCatalog,
  moduleDocPaths,
  moduleFromManifest,
  registryJson,
  rewriteModuleLinks,
} from './module-catalog.mjs'

function manifest(overrides = {}) {
  return {
    id: 'sample',
    name: { en_US: 'Sample', zh_TW: '範例' },
    description: { en_US: 'Example module.', zh_TW: '範例模塊。' },
    version: '1.0.0',
    authors: ['Tester'],
    license: 'MIT',
    capabilities: [],
    patches: [],
    ...overrides,
  }
}

async function fixture(modules) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'iimp-catalog-'))
  for (const [directory, data] of Object.entries(modules)) {
    const moduleDir = path.join(root, directory)
    await mkdir(moduleDir)
    if (data.manifest) await writeFile(path.join(moduleDir, 'module.json'), JSON.stringify(data.manifest))
    if (data.readme !== undefined) await writeFile(path.join(moduleDir, 'README.md'), data.readme)
    if (data.englishReadme !== undefined) {
      await writeFile(path.join(moduleDir, 'README.en.md'), data.englishReadme)
    }
  }
  return root
}

test('moduleFromManifest derives Tier B and repository docs metadata', () => {
  const result = moduleFromManifest(manifest({ patches: [{ file: 'stock.qml' }] }), 'sample')
  assert.equal(result.tierB, true)
  assert.equal(result.sourceVersion, '1.0.0')
  assert.equal(result.origin, 'https://ii.n1cat.xyz/index.json')
  assert.equal(result.docs.en_US, '/docs/en/modules/sample')
  assert.match(result.repo, /modules\/sample$/)
})

test('moduleFromManifest rejects missing locales and directory mismatches', () => {
  assert.throws(
    () => moduleFromManifest(manifest({ name: { en_US: 'Sample' } }), 'sample'),
    /name\.zh_TW/,
  )
  assert.throws(() => moduleFromManifest(manifest(), 'other'), /must match directory/)
})

test('loadModuleCatalog sorts modules and requires README files', async () => {
  const modulesDir = await fixture({
    zed: { manifest: manifest({ id: 'zed' }), readme: '# Zed\n' },
    alpha: { manifest: manifest({ id: 'alpha' }), readme: '# Alpha\n' },
  })
  const modules = await loadModuleCatalog({ modulesDir })
  assert.deepEqual(
    modules.map((module) => module.id),
    ['alpha', 'zed'],
  )

  const invalidDir = await fixture({ sample: { manifest: manifest() } })
  await assert.rejects(loadModuleCatalog({ modulesDir: invalidDir }), /README\.md is required/)
})

test('loadModuleCatalog rejects empty module roots', async () => {
  const modulesDir = await fixture({ unrelated: { readme: '# No manifest\n' } })
  await assert.rejects(loadModuleCatalog({ modulesDir }), /no modules found/)
})

test('moduleDocPaths uses English README and documents the Chinese fallback', async () => {
  const modulesDir = await fixture({
    sample: { manifest: manifest(), readme: '# 中文標題\n\n中文。' },
  })
  const [chinese] = await moduleDocPaths('zh_TW', { modulesDir })
  const [english] = await moduleDocPaths('en_US', { modulesDir })
  assert.equal(chinese.params.editPath, 'modules/sample/README.md')
  assert.match(english.content, /^# Sample/)
  assert.match(english.content, /Translation status/)
  assert.match(english.content, /中文。/)
  assert.equal(english.params.editPath, 'modules/sample/README.md')

  await writeFile(path.join(modulesDir, 'sample', 'README.en.md'), '# English details\n')
  const [translated] = await moduleDocPaths('en_US', { modulesDir })
  assert.equal(translated.content, '# English details\n')
  assert.equal(translated.params.editPath, 'modules/sample/README.en.md')
})

test('rewriteModuleLinks turns sibling module links into site pages', () => {
  const ids = ['adaptive_bar', 'clock_popup_slim']
  assert.equal(rewriteModuleLinks('see [a](../adaptive_bar/)', ids), 'see [a](./adaptive_bar)')
  assert.equal(rewriteModuleLinks('[a](../adaptive_bar)', ids), '[a](./adaptive_bar)')
  assert.equal(rewriteModuleLinks('[a](../adaptive_bar/README.md#limits)', ids), '[a](./adaptive_bar#limits)')
  assert.equal(rewriteModuleLinks('[a](../adaptive_bar/README.en.md)', ids), '[a](./adaptive_bar)')
  // Unknown modules, deeper paths, and non-module relative links are untouched.
  assert.equal(rewriteModuleLinks('[a](../unknown/)', ids), '[a](../unknown/)')
  assert.equal(rewriteModuleLinks('[a](../adaptive_bar/docs/x.md)', ids), '[a](../adaptive_bar/docs/x.md)')
  assert.equal(rewriteModuleLinks('[a](../../README.md)', ids), '[a](../../README.md)')
  assert.equal(rewriteModuleLinks('', ids), '')
  assert.equal(rewriteModuleLinks('[a](../adaptive_bar/)', []), '[a](../adaptive_bar/)')
})

test('moduleDocPaths rewrites sibling module links in both locales', async () => {
  const modulesDir = await fixture({
    other: { manifest: manifest({ id: 'other', name: { en_US: 'Other', zh_TW: '其他' } }), readme: '# 其他\n' },
    sample: { manifest: manifest(), readme: '# 範例\n\n見 [other](../other/)。' },
  })
  const chinese = (await moduleDocPaths('zh_TW', { modulesDir })).find((page) => page.params.id === 'sample')
  assert.match(chinese.content, /\]\(\.\/other\)/)
  await writeFile(path.join(modulesDir, 'sample', 'README.en.md'), '# Sample\n\nSee [other](../other/README.md).\n')
  const english = (await moduleDocPaths('en_US', { modulesDir })).find((page) => page.params.id === 'sample')
  assert.equal(english.content, '# Sample\n\nSee [other](./other).\n')
})

test('documentationEditUrl resolves generated and ordinary documentation sources', () => {
  assert.equal(
    documentationEditUrl({
      filePath: 'modules/[id].md',
      params: { id: 'sample', editPath: 'modules/sample/README.md' },
    }),
    'https://github.com/956zs/ii-modules/edit/main/modules/sample/README.md',
  )
  assert.equal(
    documentationEditUrl({ filePath: 'guide/install.md' }),
    'https://github.com/956zs/ii-modules/edit/main/site/docs/guide/install.md',
  )
})

test('registryJson excludes build-only paths and stays deterministic', () => {
  const module = {
    ...moduleFromManifest(manifest(), 'sample'),
    readmePath: '/tmp/README.md',
    moduleDir: '/tmp/sample',
  }
  const output = registryJson([module])
  assert.doesNotMatch(output, /readmePath|moduleDir/)
  assert.equal(output.endsWith('\n'), true)
})
