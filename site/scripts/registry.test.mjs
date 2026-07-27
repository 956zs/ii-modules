import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import vm from 'node:vm'

async function loadParseRegistry() {
  const source = await readFile(new URL('../src/lib/registry.ts', import.meta.url), 'utf8')
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2023 },
  }).outputText
  const body = transpiled.replace('export function parseRegistry', 'function parseRegistry')
  const context = vm.createContext({})
  vm.runInContext(`${body}; globalThis.parseRegistry = parseRegistry`, context)
  return context.parseRegistry
}

function moduleRecord(overrides = {}) {
  return {
    id: 'sample',
    name: { en_US: 'Sample', zh_TW: '範例' },
    description: { en_US: 'Example.', zh_TW: '範例。' },
    sourceVersion: '1.0.0',
    authors: ['Tester'],
    license: 'MIT',
    tierB: false,
    capabilities: [],
    requires: {},
    origin: 'https://example.invalid/index.json',
    repo: 'https://example.invalid/repo',
    docs: { en_US: '/docs/en/modules/sample', zh_TW: '/docs/modules/sample' },
    ...overrides,
  }
}

test('parseRegistry accepts the generated registry schema', async () => {
  const parseRegistry = await loadParseRegistry()
  const registry = { modules: [moduleRecord()] }
  const parsed = parseRegistry(registry)
  assert.equal(parsed.modules.length, 1)
  assert.equal(parsed.modules[0].id, 'sample')
  assert.equal(parsed.modules[0].name.zh_TW, '範例')
})

test('parseRegistry rejects cached module records missing localized names', async () => {
  const parseRegistry = await loadParseRegistry()
  assert.throws(
    () => parseRegistry({ modules: [moduleRecord({ name: undefined })] }),
    /unsupported or incomplete schema/,
  )
})

test('parseRegistry rejects obsolete and incomplete top-level shapes', async () => {
  const parseRegistry = await loadParseRegistry()
  assert.throws(() => parseRegistry([moduleRecord()]), /unsupported or incomplete schema/)
  assert.throws(() => parseRegistry({ modules: null }), /unsupported or incomplete schema/)
})

test('useRegistry bypasses cached registry responses', async () => {
  const source = await readFile(new URL('../src/hooks/use-registry.ts', import.meta.url), 'utf8')
  assert.match(source, /fetch\([^\n]+\{ cache: 'no-store' \}\)/)
  assert.match(source, /\.then\(parseRegistry\)/)
})
