import assert from 'node:assert/strict'
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises'
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
    assets: [
      { name: assetName, browser_download_url: url },
      { name: 'SHA256SUMS', browser_download_url: `${url}.sums` },
    ],
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
  const moduleUrl = 'https://github.com/example/repo/releases/download/module%2Fsample%2Fv2.0.0/sample-2.0.0.iimod'
  const cliUrl = 'https://github.com/example/repo/releases/download/iimod%2Fv3.1.0/iimod-linux-x86_64'
  const downloads = new Map([
    [moduleUrl, Buffer.from('abc')],
    [cliUrl, Buffer.from('hello')],
  ])
  const releases = [
    release('module/sample/v1.9.0', 'sample-1.9.0.iimod', 'https://github.com/example/repo/releases/download/old/sample.iimod'),
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
      overrides.moduleUrl ?? 'https://github.com/example/repo/releases/download/module%2Fsample%2Fv1.0.0/sample-1.0.0.iimod',
      overrides.moduleOverrides,
    ),
    release(
      overrides.cliTag ?? 'iimod/v1.0.0',
      overrides.cliAsset ?? 'iimod-linux-x86_64',
      overrides.cliUrl ?? 'https://github.com/example/repo/releases/download/iimod%2Fv1.0.0/iimod-linux-x86_64',
      overrides.cliOverrides,
    ),
  ]
}

async function assertProjectionRejects(
  releases,
  pattern,
  download = async () => Buffer.from('bytes'),
) {
  const outputs = await outputFixture()
  await writeFile(outputs.indexOutput, 'existing index')
  await assert.rejects(
    projectReleases({
      releases,
      ...outputs,
      download,
    }),
    pattern,
  )
  assert.equal(await readFile(outputs.indexOutput, 'utf8'), 'existing index')
  await assert.rejects(readFile(outputs.cliOutput), { code: 'ENOENT' })
}

test('rejects duplicate releases, ambiguous precedence, and invalid stable tags', async () => {
  await assertProjectionRejects(
    [...validPair(), release('module/sample/v1.0.0', 'sample-1.0.0.iimod', 'https://github.com/example/repo/releases/download/duplicate/sample-1.0.0.iimod')],
    /duplicate release/,
  )
  await assertProjectionRejects(
    [...validPair(), release('module/sample/v1.0.0+build2', 'sample-1.0.0+build2.iimod', 'https://github.com/example/repo/releases/download/build2/sample-1.0.0+build2.iimod')],
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
    [...validPair(), release('iimod/latest', 'iimod-linux-x86_64', 'https://github.com/example/repo/releases/download/a/b')],
    /invalid namespaced release tag/,
  )
  await assertProjectionRejects(
    [...validPair(), release('module/sample_/v1.0.0', 'sample_-1.0.0.iimod', 'https://github.com/example/repo/releases/download/a/b')],
    /invalid IIMP module id/,
  )
  await assertProjectionRejects(
    [...validPair(), release('module/sample__bad/v1.0.0', 'sample__bad-1.0.0.iimod', 'https://github.com/example/repo/releases/download/a/b')],
    /invalid IIMP module id/,
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

test('requires the release to contain only its product artifact and SHA256SUMS', async () => {
  await assertProjectionRejects(
    validPair({ moduleAsset: 'sample.iimod' }),
    /release assets must be exactly/,
  )
  const duplicate = validPair()
  duplicate[0].assets.push({ ...duplicate[0].assets[0] })
  await assertProjectionRejects(duplicate, /release assets must be exactly/)
  const mixed = validPair()
  mixed[0].assets.push({
    name: 'iimod-linux-x86_64',
    browser_download_url: 'https://github.com/example/repo/releases/download/mixed/iimod-linux-x86_64',
  })
  await assertProjectionRejects(mixed, /release assets must be exactly/)
  const missingChecksums = validPair()
  missingChecksums[0].assets = [missingChecksums[0].assets[0]]
  await assertProjectionRejects(missingChecksums, /release assets must be exactly/)
})

test('requires an absolute GitHub HTTPS product download URL', async () => {
  await assertProjectionRejects(
    validPair({ moduleUrl: '/sample-1.0.0.iimod' }),
    /absolute GitHub HTTPS/,
  )
  await assertProjectionRejects(
    validPair({ moduleUrl: 'http://github.com/example/repo/releases/download/tag/sample.iimod' }),
    /absolute GitHub HTTPS/,
  )
  await assertProjectionRejects(
    validPair({ moduleUrl: 'https://downloads.example/sample-1.0.0.iimod' }),
    /absolute GitHub HTTPS/,
  )
})

test('ignores drafts and prereleases and projects the remaining product set', async () => {
  const noCli = await outputFixture()
  await mkdir(path.dirname(noCli.cliOutput), { recursive: true })
  await writeFile(noCli.cliOutput, 'stale binary')
  await writeFile(`${noCli.cliOutput}.sha256`, 'stale checksum')
  const moduleOnly = await projectReleases({
    releases: validPair({ cliOverrides: { draft: true } }),
    ...noCli,
    download: async () => Buffer.from('module bytes'),
  })
  assert.deepEqual(Object.keys(moduleOnly.modules), ['sample'])
  await assert.rejects(readFile(noCli.cliOutput), { code: 'ENOENT' })
  await assert.rejects(readFile(`${noCli.cliOutput}.sha256`), { code: 'ENOENT' })

  const noModules = await outputFixture()
  const cliOnly = await projectReleases({
    releases: validPair({ moduleOverrides: { prerelease: true } }),
    ...noModules,
    download: async () => Buffer.from('cli bytes'),
  })
  assert.deepEqual(cliOnly, { indexVersion: 1, modules: {} })
  assert.equal((await readFile(noModules.cliOutput)).toString(), 'cli bytes')
})

test('rejects empty and oversized downloaded assets without changing outputs', async () => {
  await assertProjectionRejects(validPair(), /asset size 0 is outside/, async () => Buffer.alloc(0))
  await assertProjectionRejects(
    validPair(),
    /asset size 20971521 is outside/,
    async () => Buffer.alloc(20 * 1024 * 1024 + 1),
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

function runScript(args, env = {}) {
  return new Promise((resolve) => {
    const child = spawn(
      process.execPath,
      [fileURLToPath(new URL('./release-projection.mjs', import.meta.url)), ...args],
      { env: { ...process.env, ...env } },
    )
    let stderr = ''
    child.stderr.setEncoding('utf8')
    child.stderr.on('data', (chunk) => {
      stderr += chunk
    })
    child.on('close', (code) => resolve({ code, stderr }))
  })
}

test('Pages workflow projects into the site dist directory that it uploads', async () => {
  const workflow = await readFile(new URL('../../.github/workflows/pages.yml', import.meta.url), 'utf8')
  assert.match(workflow, /npm --prefix site run releases:project/)
  assert.match(workflow, /--index-output dist\/index\.json/)
  assert.match(workflow, /--cli-output dist\/downloads\/iimod\/linux-x86_64/)
  assert.match(workflow, /path: site\/dist/)
  assert.doesNotMatch(workflow, /--(?:index|cli)-output site\/dist\//)
})

test('CLI accepts comma-separated paginated API fixtures with offline HTTPS downloads', async () => {
  const outputs = await outputFixture()
  const moduleUrl = 'https://github.com/example/repo/releases/download/module%2Fsample%2Fv1.0.0/sample-1.0.0.iimod'
  const cliUrl = 'https://github.com/example/repo/releases/download/iimod%2Fv1.0.0/iimod-linux-x86_64'
  const pageOne = path.join(outputs.root, 'page-1.json')
  const pageTwo = path.join(outputs.root, 'page-2.json')
  const preload = path.join(outputs.root, 'fetch-stub.mjs')
  await writeFile(pageOne, JSON.stringify([release('module/sample/v1.0.0', 'sample-1.0.0.iimod', moduleUrl)]))
  await writeFile(pageTwo, JSON.stringify([release('iimod/v1.0.0', 'iimod-linux-x86_64', cliUrl)]))
  await writeFile(
    preload,
    `globalThis.fetch = async (url) => new Response(url.endsWith('iimod-linux-x86_64') ? 'cli bytes' : 'module bytes')\n`,
  )

  const result = await runScript(
    [
      '--releases',
      `${pageOne},${pageTwo}`,
      '--index-output',
      outputs.indexOutput,
      '--cli-output',
      outputs.cliOutput,
    ],
    { NODE_OPTIONS: `--import=${preload}` },
  )
  assert.equal(result.code, 0, result.stderr)
  assert.equal((await readFile(outputs.cliOutput)).toString(), 'cli bytes')
})
