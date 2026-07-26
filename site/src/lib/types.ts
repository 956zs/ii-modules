export interface LocalizedString {
  en_US: string
  zh_TW: string
  [locale: string]: string | undefined
}

export interface RegistryModule {
  id: string
  name: LocalizedString
  description: LocalizedString
  tierB: boolean
  capabilities: string[]
  origin: string
  repo: string
}

export interface Registry {
  modules: RegistryModule[]
}

export interface ModuleVersionInfo {
  version: string
  url: string
  /** Unobtainable via the GitHub-API metadata-only fallback (no CORS-readable asset content). */
  sha256: string | null
}

export type VersionState =
  | { status: 'loading' }
  | { status: 'success'; data: ModuleVersionInfo }
  | { status: 'error' }
