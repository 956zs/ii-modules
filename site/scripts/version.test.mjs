import assert from 'node:assert/strict'
import test from 'node:test'
import ts from 'typescript'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'

async function loadVersionExports() {
  const source = await readFile(new URL('../src/lib/version.ts', import.meta.url), 'utf8')
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2023 },
  }).outputText
  const parseEntryMatch = transpiled.match(/export function parseIndexJson[\s\S]*?\n}\n/)
  const parseIndexMatch = transpiled.match(/export function parseIndex\([\s\S]*?\n}\n/)
  assert.ok(parseEntryMatch, 'parseIndexJson export not found')
  assert.ok(parseIndexMatch, 'parseIndex export not found')
  const helperMatch = transpiled.match(/function hasOnlyKeys[\s\S]*?\n}\n/)
  assert.ok(helperMatch, 'hasOnlyKeys helper not found')
  const body = `${parseEntryMatch[0]}\n${parseIndexMatch[0]}\n${helperMatch[0]}`.replaceAll(
    'export function',
    'function',
  )
  const context = vm.createContext({ URL, Object, Set })
  vm.runInContext(
    `${body}; globalThis.versionExports = { parseIndexJson, parseIndex }`,
    context,
  )
  return context.versionExports
}

test('release index parsing selects the requested module and resolves relative URLs', async () => {
  const { parseIndexJson } = await loadVersionExports()
  const origin = 'https://example.test/releases/index.json'
  const result = parseIndexJson(
    {
      indexVersion: 1,
      modules: {
        alpha: { version: '1.0.0', url: 'alpha-1.0.0.iimod', sha256: 'a'.repeat(64) },
        beta: { version: '2.0.0', url: 'beta-2.0.0.iimod', sha256: 'd'.repeat(64) },
      },
    },
    'beta',
    origin,
  )
  assert.equal(result.version, '2.0.0')
  assert.equal(result.url, 'https://example.test/releases/beta-2.0.0.iimod')
  assert.equal(result.sha256, 'd'.repeat(64))
})

test('release index parsing rejects unsafe URLs, malformed versions, and bad hashes', async () => {
  const { parseIndexJson } = await loadVersionExports()
  const origin = 'https://example.test/index.json'
  const base = { version: '1.0.0', url: 'sample-1.0.0.iimod', sha256: 'a'.repeat(64) }

  assert.equal(
    parseIndexJson({ modules: { sample: { ...base, url: 'http://example.test/a.iimod' } } }, 'sample', origin),
    null,
  )
  assert.equal(
    parseIndexJson({ modules: { sample: { ...base, version: '1.0.0-rc.1' } } }, 'sample', origin),
    null,
  )
  const built = parseIndexJson(
    { modules: { sample: { ...base, version: '1.0.0+build.1' } } },
    'sample',
    origin,
  )
  assert.equal(built.version, '1.0.0+build.1')
  assert.equal(
    parseIndexJson({ modules: { sample: { ...base, sha256: 'abc' } } }, 'sample', origin),
    null,
  )
})

test('release index distinguishes unreleased modules from invalid indexes', async () => {
  const { parseIndex } = await loadVersionExports()
  const origin = 'https://example.test/index.json'
  assert.equal(parseIndex({ indexVersion: 1, modules: {} }, 'missing', origin).status, 'unreleased')
  assert.equal(
    parseIndex({ indexVersion: 1, modules: {}, cli: { version: '1.0.0' } }, 'missing', origin)
      .status,
    'error',
  )
  assert.equal(parseIndex({ indexVersion: 2, modules: {} }, 'sample', origin).status, 'error')
  assert.equal(parseIndex({ indexVersion: 1 }, 'sample', origin).status, 'error')
  assert.equal(
    parseIndex(
      {
        indexVersion: 1,
        modules: { sample: { version: '1.0.0', url: '', sha256: 'a'.repeat(64) } },
      },
      'sample',
      origin,
    ).status,
    'error',
  )
  assert.equal(
    parseIndex(
      {
        indexVersion: 1,
        modules: {
          sample: {
            version: '1.0.0',
            url: 'sample-1.0.0.iimod',
            sha256: 'a'.repeat(64),
            notes: 'unexpected',
          },
        },
      },
      'sample',
      origin,
    ).status,
    'error',
  )
})
