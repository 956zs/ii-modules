export interface LocalizedString {
  en_US: string
  zh_TW: string
  [locale: string]: string | undefined
}

export interface RegistryModule {
  id: string
  name: LocalizedString
  description: LocalizedString
  sourceVersion: string
  authors: string[]
  license: string
  tierB: boolean
  capabilities: string[]
  requires: Record<string, unknown>
  origin: string
  repo: string
  docs: Pick<LocalizedString, 'en_US' | 'zh_TW'>
}

export interface Registry {
  modules: RegistryModule[]
}

export interface ModuleVersionInfo {
  version: string
  url: string
  sha256: string
}

export type VersionResolution =
  | { status: 'released'; data: ModuleVersionInfo }
  | { status: 'unreleased' }
  | { status: 'error' }

export type VersionState =
  | { status: 'loading' }
  | { status: 'success'; data: ModuleVersionInfo }
  | { status: 'waiting'; data?: ModuleVersionInfo }
  | { status: 'error' }
