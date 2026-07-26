import { useMemo, useState } from 'react'
import { Search } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { ModuleCard } from '@/components/module-card'
import type { RegistryModule, VersionState } from '@/lib/types'

interface ModuleGridProps {
  modules: RegistryModule[]
  versions: Record<string, VersionState>
}

function matches(mod: RegistryModule, query: string): boolean {
  const haystack = [mod.name.zh_TW, mod.name.en_US, mod.description.zh_TW, mod.description.en_US, mod.id]
    .join(' ')
    .toLowerCase()
  return haystack.includes(query.toLowerCase())
}

export function ModuleGrid({ modules, versions }: ModuleGridProps) {
  const [query, setQuery] = useState('')

  const filtered = useMemo(
    () => (query.trim() ? modules.filter((mod) => matches(mod, query)) : modules),
    [modules, query],
  )

  return (
    <section className="mx-auto flex max-w-6xl flex-col gap-6 px-6 pb-24">
      <div className="relative max-w-sm">
        <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="搜尋模塊名稱或描述…"
          className="pl-9"
          aria-label="搜尋模塊"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="py-12 text-center text-sm text-muted-foreground">找不到符合的模塊。</p>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((mod) => (
            <ModuleCard key={mod.id} module={mod} version={versions[mod.id] ?? { status: 'loading' }} />
          ))}
        </div>
      )}
    </section>
  )
}
