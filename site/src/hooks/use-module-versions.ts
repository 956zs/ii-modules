import { useEffect, useRef, useState } from 'react'
import { resolveModuleVersion } from '@/lib/version'
import type { RegistryModule, VersionState } from '@/lib/types'

/**
 * Resolves live version info for a set of registry modules in parallel,
 * updating each module's entry independently as its fetch settles so the
 * grid can render per-card skeletons instead of blocking on the slowest one.
 */
export function useModuleVersions(modules: RegistryModule[]): Record<string, VersionState> {
  const [versions, setVersions] = useState<Record<string, VersionState>>({})
  const requested = useRef(new Set<string>())

  useEffect(() => {
    for (const mod of modules) {
      if (requested.current.has(mod.id)) continue
      requested.current.add(mod.id)

      setVersions((prev) => ({ ...prev, [mod.id]: { status: 'loading' } }))
      resolveModuleVersion(mod)
        .then((resolution) => {
          setVersions((prev) => ({
            ...prev,
            [mod.id]:
              resolution.status === 'released'
                ? {
                    status:
                      resolution.data.version === mod.sourceVersion ? 'success' : 'waiting',
                    data: resolution.data,
                  }
                : resolution.status === 'unreleased'
                  ? { status: 'waiting' }
                  : { status: 'error' },
          }))
        })
        .catch(() => {
          setVersions((prev) => ({ ...prev, [mod.id]: { status: 'error' } }))
        })
    }
  }, [modules])

  return versions
}
