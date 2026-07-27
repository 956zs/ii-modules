import type { ModuleVersionInfo, RegistryModule, VersionResolution } from '@/lib/types'

const SUCCESS_CACHE_TTL_MS = 10 * 60 * 1000
const FAILURE_CACHE_TTL_MS = 60 * 1000
const CACHE_VERSION = 2

interface CacheEntry {
  timestamp: number
  ttl: number
  data: VersionResolution
}

function cacheKey(origin: string, moduleId: string): string {
  return `iimp:version:v${CACHE_VERSION}:${origin}:${moduleId}`
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
  if (!hasOnlyKeys(record, ['version', 'url', 'sha256'])) return null
  const version = typeof record.version === 'string' ? record.version : ''
  const rawUrl = typeof record.url === 'string' ? record.url : ''
  const sha256 = typeof record.sha256 === 'string' ? record.sha256.toLowerCase() : ''
  if (!/^\d+\.\d+\.\d+(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/.test(version)) return null
  if (!rawUrl.trim()) return null
  if (!/^[0-9a-f]{64}$/.test(sha256)) return null

  let url: URL
  try {
    url = new URL(rawUrl, origin)
  } catch {
    return null
  }
  if (url.protocol !== 'https:') return null

  return {
    version,
    url: url.toString(),
    sha256,
  }
}

export function parseIndex(
  json: Record<string, unknown>,
  moduleId: string,
  origin: string,
): VersionResolution {
  if (!hasOnlyKeys(json, ['indexVersion', 'modules'])) return { status: 'error' }
  if (json.indexVersion !== 1) return { status: 'error' }
  if (!json.modules || typeof json.modules !== 'object' || Array.isArray(json.modules)) {
    return { status: 'error' }
  }
  if (!Object.hasOwn(json.modules, moduleId)) return { status: 'unreleased' }
  const data = parseIndexJson(json, moduleId, origin)
  return data ? { status: 'released', data } : { status: 'error' }
}

function hasOnlyKeys(record: Record<string, unknown>, allowed: readonly string[]): boolean {
  const allowedKeys = new Set(allowed)
  return Object.keys(record).every((key) => allowedKeys.has(key))
}

/** Resolves release metadata without treating source metadata as a download. */
export async function resolveModuleVersion(mod: RegistryModule): Promise<VersionResolution> {
  const cached = readCache(mod.origin, mod.id)
  if (cached) return cached

  const index = await fetchJson(mod.origin, {
    cache: 'no-store',
    headers: { Accept: 'application/json' },
  })
  const resolved: VersionResolution = index ? parseIndex(index, mod.id, mod.origin) : { status: 'error' }

  writeCache(
    mod.origin,
    mod.id,
    resolved,
    resolved.status === 'released' ? SUCCESS_CACHE_TTL_MS : FAILURE_CACHE_TTL_MS,
  )
  return resolved
}
