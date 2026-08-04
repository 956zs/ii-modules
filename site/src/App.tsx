import { CloudAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from '@/components/ui/empty'
import { TooltipProvider } from '@/components/ui/tooltip'
import { Hero } from '@/components/hero'
import { ModuleGrid } from '@/components/module-grid'
import { SiteFooter } from '@/components/site-footer'
import { SiteHeader } from '@/components/site-header'
import { useRegistry } from '@/hooks/use-registry'
import { useModuleVersions } from '@/hooks/use-module-versions'
import { useI18n } from '@/lib/i18n'

function App() {
  const { t } = useI18n()
  const registry = useRegistry()
  const modules = registry.status === 'success' ? registry.modules : []
  const versions = useModuleVersions(modules)
  const firstModule = modules[0]

  return (
    <TooltipProvider>
      {/* No bg on this wrapper: body paints the canvas background, letting the
          fixed z-[-1] backdrop layer sit between canvas and content. */}
      <div id="top" className="min-h-svh text-foreground">
        <div aria-hidden="true" className="site-backdrop" />
        <SiteHeader />

        <Hero
          firstModule={firstModule}
          firstModuleVersion={firstModule ? versions[firstModule.id] : undefined}
          registryFailed={registry.status === 'error'}
        />

        {registry.status === 'error' ? (
          <div className="mx-auto max-w-6xl px-4 pb-24 sm:px-6">
            <Empty className="border border-dashed border-border py-16">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <CloudAlert />
                </EmptyMedia>
                <EmptyTitle>{t.registryErrorTitle}</EmptyTitle>
                <EmptyDescription>{t.registryErrorDescription}</EmptyDescription>
              </EmptyHeader>
              <Button variant="outline" size="sm" onClick={() => window.location.reload()}>
                {t.reload}
              </Button>
            </Empty>
          </div>
        ) : (
          <ModuleGrid modules={modules} versions={versions} loading={registry.status === 'loading'} />
        )}

        <SiteFooter />
      </div>
    </TooltipProvider>
  )
}

export default App
