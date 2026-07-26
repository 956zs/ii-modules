import { TooltipProvider } from '@/components/ui/tooltip'
import { Hero } from '@/components/hero'
import { ModuleGrid } from '@/components/module-grid'
import { SiteFooter } from '@/components/site-footer'
import { useRegistry } from '@/hooks/use-registry'
import { useModuleVersions } from '@/hooks/use-module-versions'

function App() {
  const registry = useRegistry()
  const modules = registry.status === 'success' ? registry.modules : []
  const versions = useModuleVersions(modules)
  const firstModule = modules[0]

  return (
    <TooltipProvider>
      <div className="min-h-svh bg-background text-foreground">
        <Hero firstModule={firstModule} firstModuleVersion={firstModule ? versions[firstModule.id] : undefined} />

        {registry.status === 'error' ? (
          <p className="mx-auto max-w-6xl px-6 pb-24 text-center text-sm text-muted-foreground">
            模塊清單暫時無法取得，請稍後再試。
          </p>
        ) : (
          <ModuleGrid modules={modules} versions={versions} />
        )}

        <SiteFooter />
      </div>
    </TooltipProvider>
  )
}

export default App
