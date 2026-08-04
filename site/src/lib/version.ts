import type { ModuleVersionInfo, RegistryModule, VersionResolution } from '@/lib/types'

const SUCCESS_CACHE_TTL_MS = 10 * 60 * 1000
const FAILURE_CACHE_TTL_MS = 60 * 1000

interface CacheEntry {
  timestamp: number
  ttl: number
  data: VersionResolution
}

function cacheKey(origin: string, moduleId: string): string {
  return `iimp:version:${origin}:${moduleId}`
}

function readCache(origin: string, moduleId: string): VersionResolution | null {
  try {
    const raw = sessionStorage.getItem(cacheKey(origin, moduleId))
    if (!raw) return null
    const entry = JSON.parse(raw) as CacheEntry
    if (Date.now() - entry.timestamp > entry.ttl) return null
    return entry.data
  } catch {
    return null
  }
}

function writeCache(origin: string, moduleId: string, data: VersionResolution, ttl: number): void {
  try {
    const entry: CacheEntry = { timestamp: Date.now(), ttl, data }
    sessionStorage.setItem(cacheKey(origin, moduleId), JSON.stringify(entry))
  } catch {
    // sessionStorage unavailable (private mode / quota) — skip caching silently.
  }
}

function parseOwnerRepoFromOrigin(origin: string): { owner: string; repo: string } | null {
  try {
    const url = new URL(origin)
    if (url.hostname !== 'github.com') return null
    const [owner, repo] = url.pathname.replace(/^\//, '').split('/')
    if (!owner || !repo) return null
    return { owner, repo }
  } catch {
    return null
  }
}

async function fetchJson(input: string, init?: RequestInit): Promise<Record<string, unknown> | null> {
  try {
    const res = await fetch(input, init)
    if (!res.ok) return null
    return (await res.json()) as Record<string, unknown>
  } catch {
    return null
  }
}

/** Reads one module from the release index contract: `{ modules: { [id]: entry } }`. */
export function parseIndexJson(
  json: Record<string, unknown>,
  moduleId: string,
  origin: string,
): ModuleVersionInfo | null {
  if (!json.modules || typeof json.modules !== 'object' || Array.isArray(json.modules)) return null
  const entry = (json.modules as Record<string, unknown>)[moduleId]
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return null
  const record = entry as Record<string, unknown>
  const version = typeof record.version === 'string' ? record.version : ''
  const rawUrl = typeof record.url === 'string' ? record.url : ''
  const sha256 = typeof record.sha256 === 'string' ? record.sha256 : null
  if (!version || !rawUrl) return null
  return {
    version,
    url: new URL(rawUrl, origin).toString(),
    sha256,
  }
}

/**
 * GitHub release assets do not expose index.json through CORS. A successful API
 * response without this module's asset is authoritative evidence that the
 * source version is not released; transport/API failure remains an error.
 */
async function fetchViaGitHubApi(origin: string, moduleId: string): Promise<VersionResolution> {
  const parsed = parseOwnerRepoFromOrigin(origin)
  if (!parsed) return { status: 'error' }
  const { owner, repo } = parsed

  const release = await fetchJson(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  })
  if (!release) return { status: 'error' }

  const assets = Array.isArray(release.assets) ? (release.assets as Array<Record<string, unknown>>) : []
  const asset = assets.find(
    (candidate) =>
      typeof candidate.name === 'string' &&
      candidate.name.startsWith(`${moduleId}-`) &&
      candidate.name.endsWith('.iimod'),
  )
  if (!asset) return { status: 'unreleased' }

  const name = asset.name as string
  const url = typeof asset.browser_download_url === 'string' ? asset.browser_download_url : ''
  if (!url) return { status: 'error' }
  return {
    status: 'released',
    data: {
      version: name.slice(moduleId.length + 1, -'.iimod'.length),
      url,
      sha256: null,
    },
  }
}

/** Resolves release metadata without treating source metadata as a download. */
export async function resolveModuleVersion(mod: RegistryModule): Promise<VersionResolution> {
  const cached = readCache(mod.origin, mod.id)
  if (cached) return cached

  const direct = await fetchJson(mod.origin, { headers: { Accept: 'application/json' } })
  const directEntry = direct ? parseIndexJson(direct, mod.id, mod.origin) : null
  const resolved: VersionResolution = directEntry
    ? { status: 'released', data: directEntry }
    : await fetchViaGitHubApi(mod.origin, mod.id)

  writeCache(
    mod.origin,
    mod.id,
    resolved,
    resolved.status === 'released' ? SUCCESS_CACHE_TTL_MS : FAILURE_CACHE_TTL_MS,
  )
  return resolved
}
