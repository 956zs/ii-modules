import { readdir, readFile, stat, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const SITE_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const REPO_DIR = path.resolve(SITE_DIR, '..')
const MODULES_DIR = path.join(REPO_DIR, 'modules')
const REGISTRY_FILE = path.join(SITE_DIR, 'public', 'registry.json')
const REPO_URL = 'https://github.com/956zs/ii-modules'
const RELEASE_INDEX = `${REPO_URL}/releases/latest/download/index.json`
const REQUIRED_LOCALES = ['en_US', 'zh_TW']

function assertNonEmptyString(value, field, source) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`${source}: ${field} must be a non-empty string`)
  }
}

function validateLocalized(value, field, source) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${source}: ${field} must be an object`)
  }
  for (const locale of REQUIRED_LOCALES) {
    assertNonEmptyString(value[locale], `${field}.${locale}`, source)
  }
}

export function moduleFromManifest(manifest, directoryName, source = 'module.json') {
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
    throw new Error(`${source}: manifest must be an object`)
  }
  assertNonEmptyString(manifest.id, 'id', source)
  if (manifest.id !== directoryName) {
    throw new Error(`${source}: id ${manifest.id} must match directory ${directoryName}`)
  }
  validateLocalized(manifest.name, 'name', source)
  validateLocalized(manifest.description, 'description', source)
  assertNonEmptyString(manifest.version, 'version', source)
  if (!Array.isArray(manifest.authors) || manifest.authors.length === 0) {
    throw new Error(`${source}: authors must be a non-empty array`)
  }
  manifest.authors.forEach((author, index) =>
    assertNonEmptyString(author, `authors[${index}]`, source),
  )
  assertNonEmptyString(manifest.license, 'license', source)
  if (!Array.isArray(manifest.capabilities)) {
    throw new Error(`${source}: capabilities must be an array`)
  }

  return {
    id: manifest.id,
    name: manifest.name,
    description: manifest.description,
    sourceVersion: manifest.version,
    authors: manifest.authors,
    license: manifest.license,
    capabilities: manifest.capabilities,
    requires: manifest.requires ?? {},
    tierB: Array.isArray(manifest.patches) && manifest.patches.length > 0,
    origin: RELEASE_INDEX,
    repo:
      typeof manifest.homepage === 'string' && manifest.homepage
        ? manifest.homepage
        : `${REPO_URL}/tree/main/modules/${manifest.id}`,
    docs: {
      zh_TW: `/docs/modules/${manifest.id}`,
      en_US: `/docs/en/modules/${manifest.id}`,
    },
  }
}

export async function loadModuleCatalog({ modulesDir = MODULES_DIR } = {}) {
  const entries = await readdir(modulesDir, { withFileTypes: true })
  const directories = entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort()
  const modules = []
  const ids = new Set()

  for (const directoryName of directories) {
    const moduleDir = path.join(modulesDir, directoryName)
    const manifestPath = path.join(moduleDir, 'module.json')
    const readmePath = path.join(moduleDir, 'README.md')
    try {
      if (!(await stat(manifestPath)).isFile()) continue
    } catch (error) {
      if (error?.code === 'ENOENT') continue
      throw error
    }

    try {
      if (!(await stat(readmePath)).isFile()) throw new Error('not a file')
    } catch {
      throw new Error(`${readmePath}: README.md is required`)
    }

    let manifest
    try {
      manifest = JSON.parse(await readFile(manifestPath, 'utf8'))
    } catch (error) {
      throw new Error(`${manifestPath}: invalid JSON (${error.message})`)
    }
    const module = moduleFromManifest(manifest, directoryName, manifestPath)
    if (ids.has(module.id)) throw new Error(`${manifestPath}: duplicate module id ${module.id}`)
    ids.add(module.id)
    modules.push({ ...module, readmePath, moduleDir })
  }

  if (modules.length === 0) throw new Error(`${modulesDir}: no modules found`)
  return modules
}

export function registryJson(modules) {
  const publicModules = modules.map(
    ({ readmePath: _readmePath, moduleDir: _moduleDir, ...module }) => module,
  )
  return `${JSON.stringify({ modules: publicModules }, null, 2)}\n`
}

export async function moduleDocPaths(locale, options) {
  if (!REQUIRED_LOCALES.includes(locale)) throw new Error(`Unsupported locale: ${locale}`)
  const modules = await loadModuleCatalog(options)
  return Promise.all(
    modules.map(async (module) => {
      const readme = await readFile(module.readmePath, 'utf8')
      if (locale === 'zh_TW') return { params: { id: module.id }, content: readme }

      const englishReadme = path.join(module.moduleDir, 'README.en.md')
      try {
        return { params: { id: module.id }, content: await readFile(englishReadme, 'utf8') }
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error
      }
      const body = readme.replace(/^# .*(?:\r?\n)+/, '')
      return {
        params: { id: module.id },
        content: `# ${module.name.en_US}\n\n::: info Translation status\nAn English README is not available yet. The module metadata above is localized; the detailed README below is shown in Traditional Chinese.\n:::\n\n${body}`,
      }
    }),
  )
}

async function main() {
  const check = process.argv.includes('--check')
  const modules = await loadModuleCatalog()
  const expected = registryJson(modules)
  if (check) {
    const actual = await readFile(REGISTRY_FILE, 'utf8').catch(() => '')
    if (actual !== expected) {
      throw new Error('public/registry.json is stale; run npm run catalog:generate')
    }
    console.log(`catalog is current (${modules.length} modules)`)
    return
  }
  await writeFile(REGISTRY_FILE, expected)
  console.log(`generated public/registry.json (${modules.length} modules)`)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message)
    process.exitCode = 1
  })
}
