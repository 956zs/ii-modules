import { useEffect, useState } from 'react'
import type { RegistryModule } from '@/lib/types'
import { parseRegistry } from '@/lib/registry'

export type RegistryState =
  | { status: 'loading' }
  | { status: 'success'; modules: RegistryModule[] }
  | { status: 'error' }

/** Loads the manifest-derived module catalog generated into public/registry.json. */
export function useRegistry(): RegistryState {
  const [state, setState] = useState<RegistryState>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    fetch(`${import.meta.env.BASE_URL}registry.json`, { cache: 'no-store' })
      .then((res) => {
        if (!res.ok) throw new Error(`registry.json ${res.status}`)
        return res.json() as Promise<unknown>
      })
      .then(parseRegistry)
      .then((data) => {
        if (!cancelled) setState({ status: 'success', modules: data.modules })
      })
      .catch(() => {
        if (!cancelled) setState({ status: 'error' })
      })
    return () => {
      cancelled = true
    }
  }, [])

  return state
}
