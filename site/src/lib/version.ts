import type { ModuleVersionInfo, RegistryModule } from '@/lib/types'

const CACHE_TTL_MS = 10 * 60 * 1000

interface CacheEntry {
  timestamp: number
  data: ModuleVersionInfo
}

function cacheKey(origin: string): string {
  return `iimp:version:${origin}`
}

function readCache(origin: string): ModuleVersionInfo | null {
  try {
    const raw = sessionStorage.getItem(cacheKey(origin))
    if (!raw) return null
    const entry = JSON.parse(raw) as CacheEntry
    if (Date.now() - entry.timestamp > CACHE_TTL_MS) return null
    return entry.data
  } catch {
    return null
  }
}

function writeCache(origin: string, data: ModuleVersionInfo): void {
  try {
    const entry: CacheEntry = { timestamp: Date.now(), data }
    sessionStorage.setItem(cacheKey(origin), JSON.stringify(entry))
  } catch {
    // sessionStorage unavailable (private mode / quota) — skip caching silently.
  }
}

function parseOwnerRepo(repoUrl: string): { owner: string; repo: string } | null {
  try {
    const url = new URL(repoUrl)
    const [owner, repo] = url.pathname.replace(/^\//, '').replace(/\.git$/, '').split('/')
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

/** Direct fetch of the registry-declared `origin` index.json. */
async function fetchDirect(origin: string): Promise<Record<string, unknown> | null> {
  return fetchJson(origin, { headers: { Accept: 'application/json' } })
}

/**
 * Fallback path when the direct fetch fails CORS (typical for github.com
 * release-asset redirects). Uses the CORS-enabled GitHub REST API to locate
 * the `index.json` release asset, then tries its public download URL before
 * falling back to the authenticated-shape API asset endpoint.
 */
async function fetchViaGitHubApi(repoUrl: string): Promise<Record<string, unknown> | null> {
  const parsed = parseOwnerRepo(repoUrl)
  if (!parsed) return null
  const { owner, repo } = parsed

  const release = await fetchJson(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  })
  if (!release) return null

  const assets = Array.isArray(release.assets) ? (release.assets as Array<Record<string, unknown>>) : []
  const asset = assets.find((a) => a.name === 'index.json')
  if (!asset) return null

  const downloadUrl = typeof asset.browser_download_url === 'string' ? asset.browser_download_url : null
  if (downloadUrl) {
    const viaDownload = await fetchJson(downloadUrl)
    if (viaDownload) return viaDownload
  }

  const assetId = asset.id
  if (typeof assetId === 'number') {
    const viaApiAsset = await fetchJson(
      `https://api.github.com/repos/${owner}/${repo}/releases/assets/${assetId}`,
      { headers: { Accept: 'application/octet-stream' } },
    )
    if (viaApiAsset) return viaApiAsset
  }

  return null
}

/**
 * Resolves a registry module's live version info: {version, url, sha256}.
 * The package `url` in index.json may be relative to the origin's directory
 * (e.g. a GitHub "releases/latest/download/" virtual path), so it is always
 * resolved against `mod.origin` regardless of which fetch strategy succeeded.
 */
export async function resolveModuleVersion(mod: RegistryModule): Promise<ModuleVersionInfo | null> {
  const cached = readCache(mod.origin)
  if (cached) return cached

  const indexJson = (await fetchDirect(mod.origin)) ?? (await fetchViaGitHubApi(mod.repo))
  if (!indexJson) return null

  const version = typeof indexJson.version === 'string' ? indexJson.version : ''
  const rawUrl = typeof indexJson.url === 'string' ? indexJson.url : ''
  const sha256 = typeof indexJson.sha256 === 'string' ? indexJson.sha256 : ''
  if (!version || !rawUrl) return null

  const data: ModuleVersionInfo = {
    version,
    url: new URL(rawUrl, mod.origin).toString(),
    sha256,
  }
  writeCache(mod.origin, data)
  return data
}
