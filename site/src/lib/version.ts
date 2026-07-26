import type { ModuleVersionInfo, RegistryModule } from '@/lib/types'

const SUCCESS_CACHE_TTL_MS = 10 * 60 * 1000
const FAILURE_CACHE_TTL_MS = 60 * 1000

interface CacheEntry {
  timestamp: number
  ttl: number
  data: ModuleVersionInfo | null
}

function cacheKey(origin: string): string {
  return `iimp:version:${origin}`
}

function readCache(origin: string): { hit: true; data: ModuleVersionInfo | null } | { hit: false } {
  try {
    const raw = sessionStorage.getItem(cacheKey(origin))
    if (!raw) return { hit: false }
    const entry = JSON.parse(raw) as CacheEntry
    if (Date.now() - entry.timestamp > entry.ttl) return { hit: false }
    return { hit: true, data: entry.data }
  } catch {
    return { hit: false }
  }
}

function writeCache(origin: string, data: ModuleVersionInfo | null, ttl: number): void {
  try {
    const entry: CacheEntry = { timestamp: Date.now(), ttl, data }
    sessionStorage.setItem(cacheKey(origin), JSON.stringify(entry))
  } catch {
    // sessionStorage unavailable (private mode / quota) — skip caching silently.
  }
}

/** Parses `{owner, repo}` out of a GitHub origin URL, e.g. `https://github.com/{owner}/{repo}/releases/latest/download/index.json`. */
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

/** Direct fetch of the registry-declared `origin` index.json. Works for any CORS-friendly host. */
async function fetchDirect(origin: string): Promise<Record<string, unknown> | null> {
  return fetchJson(origin, { headers: { Accept: 'application/json' } })
}

function parseIndexJson(json: Record<string, unknown>, origin: string): ModuleVersionInfo | null {
  const version = typeof json.version === 'string' ? json.version : ''
  const rawUrl = typeof json.url === 'string' ? json.url : ''
  const sha256 = typeof json.sha256 === 'string' ? json.sha256 : null
  if (!version || !rawUrl) return null
  return {
    version,
    url: new URL(rawUrl, origin).toString(),
    sha256,
  }
}

/**
 * Metadata-only fallback for GitHub-hosted modules. Release-asset CONTENT
 * (release-assets.githubusercontent.com) never carries an
 * access-control-allow-origin header, so browsers can never read index.json
 * once GitHub redirects to it — not via the raw origin URL, not via
 * browser_download_url, not via the /releases/assets/{id} octet-stream
 * endpoint. Only the api.github.com JSON responses are CORS-readable, so this
 * derives version + download link from release metadata instead of fetching
 * asset content. sha256 is unobtainable this way.
 */
async function fetchViaGitHubApi(origin: string): Promise<ModuleVersionInfo | null> {
  const parsed = parseOwnerRepoFromOrigin(origin)
  if (!parsed) return null
  const { owner, repo } = parsed

  const release = await fetchJson(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  })
  if (!release) return null

  const tagName = typeof release.tag_name === 'string' ? release.tag_name : ''
  if (!tagName) return null

  const assets = Array.isArray(release.assets) ? (release.assets as Array<Record<string, unknown>>) : []
  const asset = assets.find((a) => typeof a.name === 'string' && a.name.endsWith('.iimod'))
  if (!asset) return null

  const url = typeof asset.browser_download_url === 'string' ? asset.browser_download_url : ''
  if (!url) return null

  return {
    version: tagName.replace(/^v/, ''),
    url,
    sha256: null,
  }
}

/**
 * Resolves a registry module's live version info: {version, url, sha256}.
 * Tries the registry-declared `origin` directly first (works for any
 * CORS-friendly host, and self-heals if GitHub ever adds CORS to release
 * assets). Falls back to GitHub API release metadata when the origin is a
 * github.com releases/latest/download URL, since release-asset content is
 * never readable cross-origin. Successes are cached for 10 minutes;
 * failures are cached briefly (60s) to respect the 60/hr anonymous
 * api.github.com rate limit without retry-looping.
 */
export async function resolveModuleVersion(mod: RegistryModule): Promise<ModuleVersionInfo | null> {
  const cached = readCache(mod.origin)
  if (cached.hit) return cached.data

  const direct = await fetchDirect(mod.origin)
  const data = direct ? parseIndexJson(direct, mod.origin) : null
  const resolved = data ?? (await fetchViaGitHubApi(mod.origin))

  writeCache(mod.origin, resolved, resolved ? SUCCESS_CACHE_TTL_MS : FAILURE_CACHE_TTL_MS)
  return resolved
}
