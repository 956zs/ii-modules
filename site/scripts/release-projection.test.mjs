import assert from 'node:assert/strict'
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { projectReleases } from './release-projection.mjs'

const MODULE_SHA256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
const CLI_SHA256 = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'

function release(tagName, assetName, url, overrides = {}) {
  return {
    id: overrides.id ?? tagName,
    tag_name: tagName,
    draft: false,
    prerelease: false,
    assets: [{ name: assetName, browser_download_url: url }],
    ...overrides,
  }
}

async function outputFixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'iimp-release-projection-'))
  return {
    root,
    indexOutput: path.join(root, 'index.json'),
    cliOutput: path.join(root, 'downloads', 'iimod', 'linux-x86_64'),
  }
}

test('projects highest stable namespaced releases and hashes downloaded bytes', async () => {
  const outputs = await outputFixture()
  const moduleUrl = 'https://downloads.example/sample-2.0.0.iimod'
  const cliUrl = 'https://downloads.example/iimod-linux-x86_64'
  const downloads = new Map([
    [moduleUrl, Buffer.from('abc')],
    [cliUrl, Buffer.from('hello')],
  ])
  const releases = [
    release('module/sample/v1.9.0', 'sample-1.9.0.iimod', 'https://downloads.example/old'),
    release('module/sample/v2.0.0', 'sample-2.0.0.iimod', moduleUrl),
    release('module/sample/v9.0.0', 'sample-9.0.0.iimod', 'https://downloads.example/draft', {
      draft: true,
    }),
    release('module/sample/v8.0.0', 'sample-8.0.0.iimod', 'https://downloads.example/prerelease', {
      prerelease: true,
    }),
    release('iimod/v3.1.0', 'iimod-linux-x86_64', cliUrl),
    release('unrelated/v99.0.0', 'ignored', 'https://downloads.example/ignored'),
  ]

  const result = await projectReleases({
    releases,
    ...outputs,
    download: async (url) => {
      assert.ok(downloads.has(url), `unexpected download: ${url}`)
      return downloads.get(url)
    },
  })

  assert.deepEqual(result, {
    indexVersion: 1,
    modules: {
      sample: { version: '2.0.0', url: moduleUrl, sha256: MODULE_SHA256 },
    },
  })
  assert.deepEqual(JSON.parse(await readFile(outputs.indexOutput, 'utf8')), result)
  assert.deepEqual(await readFile(outputs.cliOutput), Buffer.from('hello'))
  assert.equal(await readFile(`${outputs.cliOutput}.sha256`, 'utf8'), `${CLI_SHA256}\n`)
})

function validPair(overrides = {}) {
  return [
    release(
      overrides.moduleTag ?? 'module/sample/v1.0.0',
      overrides.moduleAsset ?? 'sample-1.0.0.iimod',
      overrides.moduleUrl ?? 'https://downloads.example/sample-1.0.0.iimod',
      overrides.moduleOverrides,
    ),
    release(
      overrides.cliTag ?? 'iimod/v1.0.0',
      overrides.cliAsset ?? 'iimod-linux-x86_64',
      overrides.cliUrl ?? 'https://downloads.example/iimod-linux-x86_64',
      overrides.cliOverrides,
    ),
  ]
}

async function assertProjectionRejects(releases, pattern) {
  const outputs = await outputFixture()
  await writeFile(outputs.indexOutput, 'existing index')
  await assert.rejects(
    projectReleases({
      releases,
      ...outputs,
      download: async () => Buffer.from('bytes'),
    }),
    pattern,
  )
  assert.equal(await readFile(outputs.indexOutput, 'utf8'), 'existing index')
  await assert.rejects(readFile(outputs.cliOutput), { code: 'ENOENT' })
}

test('rejects duplicate releases, ambiguous precedence, and invalid stable tags', async () => {
  await assertProjectionRejects(
    [...validPair(), release('module/sample/v1.0.0', 'sample-1.0.0.iimod', 'https://other.example/a')],
    /duplicate release/,
  )
  await assertProjectionRejects(
    [...validPair(), release('module/sample/v1.0.0+build2', 'sample-1.0.0+build2.iimod', 'https://other.example/b')],
    /ambiguous semver precedence/,
  )
  await assertProjectionRejects(
    validPair({ moduleTag: 'module/sample/v01.0.0', moduleAsset: 'sample-01.0.0.iimod' }),
    /not valid semver/,
  )
})

test('rejects malformed product tags instead of treating them as unrelated releases', async () => {
  await assertProjectionRejects(
    [...validPair(), release('module/Sample/v1.0.0', 'Sample-1.0.0.iimod', 'https://other.example/a')],
    /invalid namespaced release tag/,
  )
  await assertProjectionRejects(
    [...validPair(), release('iimod/latest', 'iimod-linux-x86_64', 'https://other.example/b')],
    /invalid namespaced release tag/,
  )
})

test('requires API asset digests to be canonical and match recomputed bytes', async () => {
  const matching = validPair()
  matching[0].assets[0].digest = `sha256:${CLI_SHA256}`
  matching[1].assets[0].digest = null
  const outputs = await outputFixture()
  await projectReleases({
    releases: matching,
    ...outputs,
    download: async () => Buffer.from('hello'),
  })

  const mismatching = validPair()
  mismatching[0].assets[0].digest = `sha256:${MODULE_SHA256}`
  await assertProjectionRejects(mismatching, /digest mismatch/)

  const ambiguous = validPair()
  ambiguous[0].assets[0].digest = 'sha512:abc'
  await assertProjectionRejects(ambiguous, /invalid digest/)
})

test('requires exactly one precisely named asset with an absolute download URL', async () => {
  await assertProjectionRejects(validPair({ moduleAsset: 'sample.iimod' }), /expected exactly one asset/)
  const duplicate = validPair()
  duplicate[0].assets.push({ ...duplicate[0].assets[0] })
  await assertProjectionRejects(duplicate, /expected exactly one asset.*found 2/)
  await assertProjectionRejects(validPair({ moduleUrl: '/sample-1.0.0.iimod' }), /absolute HTTP\(S\)/)
})

test('ignores drafts and prereleases but requires both stable product types', async () => {
  await assertProjectionRejects(
    validPair({ cliOverrides: { draft: true } }),
    /no stable iimod release/,
  )
  await assertProjectionRejects(
    validPair({ moduleOverrides: { prerelease: true } }),
    /no stable module releases/,
  )
})

test('download failure leaves all existing outputs untouched', async () => {
  const outputs = await outputFixture()
  await writeFile(outputs.indexOutput, 'old index')
  await mkdir(path.dirname(outputs.cliOutput), { recursive: true })
  await writeFile(outputs.cliOutput, 'old binary')
  await writeFile(`${outputs.cliOutput}.sha256`, 'old checksum')
  let calls = 0
  await assert.rejects(
    projectReleases({
      releases: validPair(),
      ...outputs,
      download: async () => {
        calls += 1
        if (calls === 2) throw new Error('network unavailable')
        return Buffer.from('downloaded module')
      },
    }),
    /network unavailable/,
  )
  assert.equal(await readFile(outputs.indexOutput, 'utf8'), 'old index')
  assert.equal(await readFile(outputs.cliOutput, 'utf8'), 'old binary')
  assert.equal(await readFile(`${outputs.cliOutput}.sha256`, 'utf8'), 'old checksum')
})

function runScript(args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [fileURLToPath(new URL('./release-projection.mjs', import.meta.url)), ...args])
    let stderr = ''
    child.stderr.setEncoding('utf8')
    child.stderr.on('data', (chunk) => {
      stderr += chunk
    })
    child.on('close', (code) => resolve({ code, stderr }))
  })
}

test('CLI accepts comma-separated paginated API fixtures and downloads through HTTP', async (t) => {
  const outputs = await outputFixture()
  const server = http.createServer((request, response) => {
    response.end(request.url === '/module' ? 'module bytes' : 'cli bytes')
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  t.after(() => server.close())
  const address = server.address()
  const base = `http://127.0.0.1:${address.port}`
  const pageOne = path.join(outputs.root, 'page-1.json')
  const pageTwo = path.join(outputs.root, 'page-2.json')
  await writeFile(pageOne, JSON.stringify([release('module/sample/v1.0.0', 'sample-1.0.0.iimod', `${base}/module`)]))
  await writeFile(pageTwo, JSON.stringify([release('iimod/v1.0.0', 'iimod-linux-x86_64', `${base}/cli`)]))

  const result = await runScript([
    '--releases',
    `${pageOne},${pageTwo}`,
    '--index-output',
    outputs.indexOutput,
    '--cli-output',
    outputs.cliOutput,
  ])
  assert.equal(result.code, 0, result.stderr)
  assert.equal((await readFile(outputs.cliOutput)).toString(), 'cli bytes')
})
