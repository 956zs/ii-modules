import assert from 'node:assert/strict'
import test from 'node:test'
import ts from 'typescript'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'

async function loadParseIndexJson() {
  const source = await readFile(new URL('../src/lib/version.ts', import.meta.url), 'utf8')
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2023 },
  }).outputText
  const match = transpiled.match(/export function parseIndexJson[\s\S]*?\n}\n/)
  assert.ok(match, 'parseIndexJson export not found')
  const body = match[0].replace('export function', 'function')
  const context = vm.createContext({ URL })
  vm.runInContext(`${body}; globalThis.parseIndexJson = parseIndexJson`, context)
  return context.parseIndexJson
}

test('release index parsing selects the requested module and resolves relative URLs', async () => {
  const parseIndexJson = await loadParseIndexJson()
  const origin = 'https://example.test/releases/index.json'
  const result = parseIndexJson(
    {
      indexVersion: 1,
      modules: {
        alpha: { version: '1.0.0', url: 'alpha-1.0.0.iimod', sha256: 'abc' },
        beta: { version: '2.0.0', url: 'beta-2.0.0.iimod', sha256: 'def' },
      },
    },
    'beta',
    origin,
  )
  assert.equal(result.version, '2.0.0')
  assert.equal(result.url, 'https://example.test/releases/beta-2.0.0.iimod')
  assert.equal(result.sha256, 'def')
})

test('release index parsing rejects missing IDs and the obsolete flat shape', async () => {
  const parseIndexJson = await loadParseIndexJson()
  const origin = 'https://example.test/index.json'
  assert.equal(parseIndexJson({ modules: {} }, 'missing', origin), null)
  assert.equal(
    parseIndexJson({ version: '1.0.0', url: 'module.iimod' }, 'sample', origin),
    null,
  )
})
