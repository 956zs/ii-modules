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
  sha256: string
}

export type VersionState =
  | { status: 'loading' }
  | { status: 'success'; data: ModuleVersionInfo }
  | { status: 'error' }
