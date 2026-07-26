import { useEffect, useMemo, useRef, useState } from 'react'
import { Plus, Search, SearchX, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from '@/components/ui/empty'
import { Input } from '@/components/ui/input'
import { Kbd } from '@/components/ui/kbd'
import { ModuleCard, ModuleCardSkeleton } from '@/components/module-card'
import { ADD_MODULE_URL } from '@/lib/urls'
import type { RegistryModule, VersionState } from '@/lib/types'

interface ModuleGridProps {
  modules: RegistryModule[]
  versions: Record<string, VersionState>
  loading?: boolean
}

function matches(mod: RegistryModule, query: string): boolean {
  const haystack = [mod.name.zh_TW, mod.name.en_US, mod.description.zh_TW, mod.description.en_US, mod.id]
    .join(' ')
    .toLowerCase()
  return haystack.includes(query.toLowerCase())
}

/** Dashed call-to-action card so a short list still reads as an open registry. */
function AddModuleCard() {
  return (
    <a
      href={ADD_MODULE_URL}
      target="_blank"
      rel="noreferrer"
      className="group flex h-full min-h-52 flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-border bg-card/20 p-6 text-center transition-colors duration-200 outline-none hover:border-brand/50 hover:bg-card/40 focus-visible:ring-2 focus-visible:ring-ring/60 motion-reduce:transition-none"
    >
      <span className="flex size-10 items-center justify-center rounded-full border border-dashed border-border text-muted-foreground transition-colors duration-200 group-hover:border-brand/50 group-hover:text-brand motion-reduce:transition-none">
        <Plus className="size-5" />
      </span>
      <span className="flex flex-col gap-1">
        <span className="text-sm font-medium">發佈你的模塊</span>
        <span className="text-xs text-muted-foreground">
          送出 PR 新增至 registry.json，立即上架
        </span>
      </span>
    </a>
  )
}

export function ModuleGrid({ modules, versions, loading }: ModuleGridProps) {
  const [query, setQuery] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)

  // `/` focuses search from anywhere (except while typing or inside a dialog).
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return
      const target = e.target as HTMLElement | null
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) return
      if (document.querySelector('[data-slot=dialog-content]')) return
      e.preventDefault()
      inputRef.current?.focus()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  const trimmed = query.trim()
  const filtered = useMemo(
    () => (trimmed ? modules.filter((mod) => matches(mod, trimmed)) : modules),
    [modules, trimmed],
  )

  return (
    <section id="modules" className="mx-auto flex max-w-6xl flex-col gap-5 px-4 pb-24 sm:px-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div className="flex items-baseline gap-3">
          <h2 className="font-heading text-xl font-semibold tracking-tight">模塊清單</h2>
          {!loading ? (
            <span className="font-mono text-xs text-muted-foreground">
              {modules.length} 個模塊
            </span>
          ) : null}
        </div>

        <div className="relative w-full sm:w-72">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Escape') {
                setQuery('')
                e.currentTarget.blur()
              }
            }}
            placeholder="搜尋模塊名稱或描述…"
            className="px-9"
            aria-label="搜尋模塊"
          />
          {query ? (
            <Button
              variant="ghost"
              size="icon-xs"
              className="absolute top-1/2 right-1.5 -translate-y-1/2 text-muted-foreground"
              aria-label="清除搜尋"
              onClick={() => {
                setQuery('')
                inputRef.current?.focus()
              }}
            >
              <X />
            </Button>
          ) : (
            <Kbd className="pointer-events-none absolute top-1/2 right-2.5 -translate-y-1/2">/</Kbd>
          )}
        </div>
      </div>

      {trimmed && filtered.length > 0 ? (
        <p role="status" className="text-xs text-muted-foreground">
          找到 {filtered.length} 個符合「{trimmed}」的模塊
        </p>
      ) : null}

      {loading ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <ModuleCardSkeleton />
          <ModuleCardSkeleton />
          <ModuleCardSkeleton />
        </div>
      ) : filtered.length === 0 ? (
        <Empty className="border border-dashed border-border py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <SearchX />
            </EmptyMedia>
            <EmptyTitle>找不到符合的模塊</EmptyTitle>
            <EmptyDescription>沒有模塊符合「{trimmed}」，換個關鍵字試試。</EmptyDescription>
          </EmptyHeader>
          <Button variant="outline" size="sm" onClick={() => setQuery('')}>
            清除搜尋
          </Button>
        </Empty>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((mod) => (
            <ModuleCard key={mod.id} module={mod} version={versions[mod.id] ?? { status: 'loading' }} />
          ))}
          {!trimmed ? <AddModuleCard /> : null}
        </div>
      )}
    </section>
  )
}
