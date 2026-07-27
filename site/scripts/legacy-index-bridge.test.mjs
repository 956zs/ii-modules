import assert from 'node:assert/strict'
import { mkdtemp, readFile, writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { legacyIndexForModule } from './legacy-index-bridge.mjs'

const digest = 'a'.repeat(64)
const entry = {
  version: '1.5.0',
  url: 'https://github.com/956zs/ii-modules/releases/download/module%2Fnetwork_traffic%2Fv1.5.0/network_traffic-1.5.0.iimod',
  sha256: digest,
}

function index(overrides = {}) {
  return { indexVersion: 1, modules: { network_traffic: { ...entry, ...overrides } } }
}

test('projects one module into the exact legacy index v1 schema', () => {
  assert.deepEqual(legacyIndexForModule(index(), 'network_traffic'), {
    indexVersion: 1,
    modules: { network_traffic: entry },
  })
})

test('rejects missing modules and invalid top-level schemas', () => {
  assert.throws(() => legacyIndexForModule({ indexVersion: 1, modules: {} }, 'network_traffic'), /no release/)
  assert.throws(() => legacyIndexForModule({ indexVersion: 2, modules: {} }, 'network_traffic'), /indexVersion 1/)
  assert.throws(() => legacyIndexForModule({ indexVersion: 1 }, 'network_traffic'), /modules must be an object/)
})

test('rejects malformed module IDs, versions, hashes, and URLs', () => {
  assert.throws(() => legacyIndexForModule(index(), 'network__traffic'), /invalid IIMP module id/)
  assert.throws(() => legacyIndexForModule(index({ version: '1.5.0-rc.1' }), 'network_traffic'), /stable semver/)
  assert.throws(() => legacyIndexForModule(index({ sha256: 'abc' }), 'network_traffic'), /64 lowercase/)
  assert.throws(() => legacyIndexForModule(index({ url: 'http://github.com/a' }), 'network_traffic'), /GitHub HTTPS/)
  assert.throws(() => legacyIndexForModule(index({ url: 'https://example.com/a' }), 'network_traffic'), /GitHub HTTPS/)
})

test('CLI writes a deterministic bridge file', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'iimp-legacy-bridge-'))
  const source = path.join(root, 'aggregate.json')
  const output = path.join(root, 'legacy', 'index.json')
  await writeFile(source, JSON.stringify(index()))
  const result = spawnSync(
    process.execPath,
    [
      fileURLToPath(new URL('./legacy-index-bridge.mjs', import.meta.url)),
      '--index',
      source,
      '--module',
      'network_traffic',
      '--output',
      output,
    ],
    { encoding: 'utf8' },
  )
  assert.equal(result.status, 0, result.stderr)
  assert.deepEqual(JSON.parse(await readFile(output, 'utf8')), legacyIndexForModule(index(), 'network_traffic'))
})
