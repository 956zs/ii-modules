import { createHash } from 'node:crypto'
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const MODULE_TAG = /^module\/([a-z][a-z0-9_]{1,30})\/v(.+)$/
const CLI_TAG = /^iimod\/v(.+)$/
const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/

function parseSemver(version) {
  const match = SEMVER.exec(version)
  if (!match) return null
  const prerelease = match[4]?.split('.') ?? []
  if (prerelease.some((part) => /^\d+$/.test(part) && part.length > 1 && part.startsWith('0'))) {
    return null
  }
  return {
    version,
    core: match.slice(1, 4).map(BigInt),
    prerelease,
  }
}

function compareSemver(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left.core[index] < right.core[index]) return -1
    if (left.core[index] > right.core[index]) return 1
  }
  if (left.prerelease.length === 0 || right.prerelease.length === 0) {
    return left.prerelease.length === right.prerelease.length ? 0 : left.prerelease.length === 0 ? 1 : -1
  }
  const length = Math.max(left.prerelease.length, right.prerelease.length)
  for (let index = 0; index < length; index += 1) {
    const a = left.prerelease[index]
    const b = right.prerelease[index]
    if (a === undefined || b === undefined) return a === undefined ? -1 : 1
    if (a === b) continue
    const aNumeric = /^\d+$/.test(a)
    const bNumeric = /^\d+$/.test(b)
    if (aNumeric && bNumeric) return BigInt(a) < BigInt(b) ? -1 : 1
    if (aNumeric !== bNumeric) return aNumeric ? -1 : 1
    return a < b ? -1 : 1
  }
  return 0
}

function releaseCandidate(release) {
  if (!release || typeof release !== 'object' || Array.isArray(release)) {
    throw new Error('release payload entries must be objects')
  }
  if (release.draft === true || release.prerelease === true) return null
  if (release.draft !== false || release.prerelease !== false) {
    throw new Error(`release ${release.tag_name ?? '<unknown>'}: draft and prerelease must be booleans`)
  }
  const tag = release.tag_name
  if (typeof tag !== 'string') throw new Error('release tag_name must be a string')
  const moduleMatch = MODULE_TAG.exec(tag)
  const cliMatch = CLI_TAG.exec(tag)
  if (!moduleMatch && !cliMatch) {
    if (tag.startsWith('module/') || tag.startsWith('iimod/')) {
      throw new Error(`${tag}: invalid namespaced release tag`)
    }
    return null
  }

  const product = moduleMatch ? `module/${moduleMatch[1]}` : 'iimod'
  const id = moduleMatch?.[1] ?? null
  const version = moduleMatch?.[2] ?? cliMatch[1]
  const semver = parseSemver(version)
  if (!semver) throw new Error(`${tag}: version is not valid semver`)
  if (semver.prerelease.length > 0) return null
  const expectedAsset = id ? `${id}-${version}.iimod` : 'iimod-linux-x86_64'
  if (!Array.isArray(release.assets)) throw new Error(`${tag}: assets must be an array`)
  const matches = release.assets.filter((asset) => asset?.name === expectedAsset)
  if (matches.length !== 1) {
    throw new Error(`${tag}: expected exactly one asset named ${expectedAsset}, found ${matches.length}`)
  }
  const url = matches[0].browser_download_url
  const apiDigest = matches[0].digest
  if (apiDigest != null && !/^sha256:[0-9a-f]{64}$/.test(apiDigest)) {
    throw new Error(`${tag}: ${expectedAsset} has invalid digest`)
  }
  try {
    const parsed = new URL(url)
    if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('unsupported protocol')
  } catch {
    throw new Error(`${tag}: ${expectedAsset} must have an absolute HTTP(S) browser_download_url`)
  }
  return { product, id, version, semver, url, apiDigest: apiDigest?.slice('sha256:'.length) ?? null }
}

function selectReleases(releases) {
  if (!Array.isArray(releases)) throw new Error('release input must be a JSON array')
  const candidates = releases.map(releaseCandidate).filter(Boolean)
  const seenVersions = new Set()
  const selected = new Map()
  for (const candidate of candidates) {
    const versionKey = `${candidate.product}\0${candidate.version}`
    if (seenVersions.has(versionKey)) {
      throw new Error(`duplicate release for ${candidate.product} v${candidate.version}`)
    }
    seenVersions.add(versionKey)
    const current = selected.get(candidate.product)
    if (!current || compareSemver(candidate.semver, current.semver) > 0) {
      selected.set(candidate.product, candidate)
    } else if (compareSemver(candidate.semver, current.semver) === 0) {
      throw new Error(`ambiguous semver precedence for ${candidate.product}: ${current.version} and ${candidate.version}`)
    }
  }
  return selected
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex')
}

async function defaultDownload(url) {
  const response = await fetch(url, { redirect: 'follow' })
  if (!response.ok) throw new Error(`download failed (${response.status}) for ${url}`)
  return Buffer.from(await response.arrayBuffer())
}

async function replaceFile(output, contents, mode) {
  await mkdir(path.dirname(output), { recursive: true })
  const temporary = `${output}.tmp-${process.pid}-${Math.random().toString(16).slice(2)}`
  try {
    await writeFile(temporary, contents, mode === undefined ? undefined : { mode })
    await rename(temporary, output)
  } finally {
    await rm(temporary, { force: true })
  }
}

export async function projectReleases({ releases, indexOutput, cliOutput, download = defaultDownload }) {
  if (typeof indexOutput !== 'string' || !indexOutput) throw new Error('indexOutput is required')
  if (typeof cliOutput !== 'string' || !cliOutput) throw new Error('cliOutput is required')
  const selected = selectReleases(releases)
  const cli = selected.get('iimod')
  if (!cli) throw new Error('no stable iimod release found')

  const moduleCandidates = [...selected.values()]
    .filter((candidate) => candidate.id !== null)
    .sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0))
  if (moduleCandidates.length === 0) throw new Error('no stable module releases found')

  const downloaded = new Map()
  for (const candidate of [...moduleCandidates, cli]) {
    let bytes
    try {
      bytes = Buffer.from(await download(candidate.url))
    } catch (error) {
      throw new Error(`failed to download ${candidate.url}: ${error.message}`)
    }
    const digest = sha256(bytes)
    if (candidate.apiDigest !== null && candidate.apiDigest !== digest) {
      throw new Error(`${candidate.product} v${candidate.version}: asset digest mismatch`)
    }
    downloaded.set(candidate.product, { bytes, digest })
  }

  const modules = Object.fromEntries(
    moduleCandidates.map((candidate) => [
      candidate.id,
      {
        version: candidate.version,
        url: candidate.url,
        sha256: downloaded.get(candidate.product).digest,
      },
    ]),
  )
  const index = { indexVersion: 1, modules }
  const cliDownload = downloaded.get('iimod')

  await replaceFile(indexOutput, `${JSON.stringify(index, null, 2)}\n`)
  await replaceFile(cliOutput, cliDownload.bytes, 0o755)
  await replaceFile(`${cliOutput}.sha256`, `${cliDownload.digest}\n`)
  return index
}

function parseArguments(argv) {
  const values = new Map()
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index]
    const value = argv[index + 1]
    if (!flag?.startsWith('--') || value === undefined) throw new Error(`invalid argument: ${flag ?? ''}`)
    if (values.has(flag)) throw new Error(`duplicate argument: ${flag}`)
    values.set(flag, value)
  }
  const allowed = new Set(['--releases', '--index-output', '--cli-output'])
  for (const flag of values.keys()) {
    if (!allowed.has(flag)) throw new Error(`unknown argument: ${flag}`)
  }
  for (const flag of allowed) {
    if (!values.has(flag)) throw new Error(`missing required argument: ${flag}`)
  }
  return values
}

async function main() {
  const args = parseArguments(process.argv.slice(2))
  const releasePaths = args.get('--releases').split(',').filter(Boolean)
  if (releasePaths.length === 0) throw new Error('--releases must name at least one JSON file')
  const pages = await Promise.all(
    releasePaths.map(async (releasePath) => {
      const source = await readFile(releasePath, 'utf8')
      try {
        return JSON.parse(source)
      } catch (error) {
        throw new Error(`${releasePath}: invalid JSON (${error.message})`)
      }
    }),
  )
  if (pages.some((page) => !Array.isArray(page))) throw new Error('each releases JSON file must contain an array')
  await projectReleases({
    releases: pages.flat(),
    indexOutput: args.get('--index-output'),
    cliOutput: args.get('--cli-output'),
  })
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message)
    process.exitCode = 1
  })
}
