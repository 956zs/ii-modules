import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const MODULE_ID = /^[a-z][a-z0-9_]{1,30}$/
const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/
const SHA256 = /^[0-9a-f]{64}$/

export function legacyIndexForModule(index, moduleId) {
  if (!MODULE_ID.test(moduleId) || moduleId.endsWith('_') || moduleId.includes('__')) {
    throw new Error(`invalid IIMP module id: ${moduleId}`)
  }
  if (!index || typeof index !== 'object' || Array.isArray(index) || index.indexVersion !== 1) {
    throw new Error('aggregate index must use indexVersion 1')
  }
  if (!index.modules || typeof index.modules !== 'object' || Array.isArray(index.modules)) {
    throw new Error('aggregate index modules must be an object')
  }
  const entry = index.modules[moduleId]
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    throw new Error(`aggregate index has no release for ${moduleId}`)
  }
  if (!SEMVER.test(entry.version)) throw new Error(`${moduleId}: version must be stable semver`)
  if (!SHA256.test(entry.sha256)) throw new Error(`${moduleId}: sha256 must be 64 lowercase hex digits`)
  let url
  try {
    url = new URL(entry.url)
  } catch {
    throw new Error(`${moduleId}: url must be absolute HTTPS`)
  }
  if (url.protocol !== 'https:' || url.hostname !== 'github.com') {
    throw new Error(`${moduleId}: url must be an absolute GitHub HTTPS URL`)
  }
  return {
    indexVersion: 1,
    modules: {
      [moduleId]: {
        version: entry.version,
        url: url.toString(),
        sha256: entry.sha256,
      },
    },
  }
}

async function replaceFile(output, contents) {
  await mkdir(path.dirname(output), { recursive: true })
  const temporary = `${output}.tmp-${process.pid}`
  try {
    await writeFile(temporary, contents)
    await rename(temporary, output)
  } finally {
    await rm(temporary, { force: true })
  }
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
  const allowed = ['--index', '--module', '--output']
  for (const flag of values.keys()) {
    if (!allowed.includes(flag)) throw new Error(`unknown argument: ${flag}`)
  }
  for (const flag of allowed) {
    if (!values.has(flag)) throw new Error(`missing required argument: ${flag}`)
  }
  return values
}

async function main() {
  const args = parseArguments(process.argv.slice(2))
  let index
  try {
    index = JSON.parse(await readFile(args.get('--index'), 'utf8'))
  } catch (error) {
    throw new Error(`${args.get('--index')}: invalid index (${error.message})`)
  }
  const bridge = legacyIndexForModule(index, args.get('--module'))
  await replaceFile(args.get('--output'), `${JSON.stringify(bridge, null, 2)}\n`)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message)
    process.exitCode = 1
  })
}
