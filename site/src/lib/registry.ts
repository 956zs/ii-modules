import type { Registry, RegistryModule } from '@/lib/types'

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim() !== ''
}

function localized(value: unknown): value is RegistryModule['name'] {
  return Boolean(
    value
      && typeof value === 'object'
      && !Array.isArray(value)
      && nonEmptyString((value as Record<string, unknown>).en_US)
      && nonEmptyString((value as Record<string, unknown>).zh_TW),
  )
}

function registryModule(value: unknown): value is RegistryModule {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const module = value as Record<string, unknown>
  return nonEmptyString(module.id)
    && localized(module.name)
    && localized(module.description)
    && nonEmptyString(module.sourceVersion)
    && Array.isArray(module.authors)
    && module.authors.every(nonEmptyString)
    && nonEmptyString(module.license)
    && typeof module.tierB === 'boolean'
    && Array.isArray(module.capabilities)
    && module.capabilities.every(nonEmptyString)
    && Boolean(module.requires && typeof module.requires === 'object' && !Array.isArray(module.requires))
    && nonEmptyString(module.origin)
    && nonEmptyString(module.repo)
    && localized(module.docs)
}

export function parseRegistry(value: unknown): Registry {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('registry.json has an unsupported or incomplete schema')
  }
  const modules = (value as Record<string, unknown>).modules
  if (!Array.isArray(modules) || !modules.every(registryModule)) {
    throw new Error('registry.json has an unsupported or incomplete schema')
  }
  return { modules }
}
