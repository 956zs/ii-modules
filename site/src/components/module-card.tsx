import { AlertTriangle, BookOpen, Download, ExternalLink } from 'lucide-react'
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { CommandBlock } from '@/components/command-block'
import { CopyButton } from '@/components/copy-button'
import { useI18n } from '@/lib/i18n'
import { installCommand } from '@/lib/install'
import { cn } from '@/lib/utils'
import type { RegistryModule, VersionState } from '@/lib/types'

function VersionBadge({ version }: { version: VersionState }) {
  const { t } = useI18n()
  if (version.status === 'loading') return <Skeleton className="h-5 w-14 rounded-full" />
  if (version.status === 'success') {
    return (
      <Badge variant="secondary" className="gap-1.5 font-mono text-[0.7rem]">
        <span className="relative flex size-1.5">
          <span className="absolute inline-flex size-full rounded-full bg-live animate-live-breathe" />
        </span>
        v{version.data.version}
      </Badge>
    )
  }
  if (version.status === 'waiting') {
    return (
      <Badge variant="outline" className="text-[0.7rem] text-muted-foreground">
        {t.waitingForRelease}
      </Badge>
    )
  }
  return (
    <Badge variant="outline" className="text-[0.7rem] text-muted-foreground">
      {t.versionUnknown}
    </Badge>
  )
}

function ModuleDetailDialog({ module: mod, version }: ModuleCardProps) {
  const { t, locale } = useI18n()
  const otherLocale = locale === 'zh_TW' ? 'en_US' : 'zh_TW'
  // Wide enough that the install command rarely wraps on desktop (w-fit would
  // break here: shrink-to-fit of a fixed element with left:50% caps available
  // width at half the viewport).
  return (
    <DialogContent className="max-h-[85svh] grid-cols-1 overflow-x-hidden overflow-y-auto *:min-w-0 sm:max-w-[min(92vw,60rem)]">
      <DialogHeader>
        <DialogTitle className="flex flex-wrap items-center gap-2 pr-8 text-lg">
          {mod.name[locale]}
          <VersionBadge version={version} />
        </DialogTitle>
        {/* zh title pairs with the English name; en title pairs with the module id
            so the subtitle never duplicates the title. */}
        <DialogDescription className="font-mono text-xs tracking-wide uppercase">
          {locale === 'zh_TW' ? mod.name.en_US : mod.id}
        </DialogDescription>
      </DialogHeader>

      <div className="flex min-w-0 flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <p className="text-sm text-foreground/90">{mod.description[locale]}</p>
          <p className="text-sm text-muted-foreground">{mod.description[otherLocale]}</p>
        </div>

        <Separator />

        <section className="flex flex-col gap-2">
          <h3 className="font-mono text-xs tracking-wide text-muted-foreground uppercase">
            {t.capabilitiesTitle}
          </h3>
          <ul className="flex flex-col gap-1.5">
            {mod.tierB ? (
              <li className="flex items-center gap-2 text-sm">
                <Badge variant="destructive" className="gap-1">
                  <AlertTriangle data-icon="inline-start" />
                  Tier B
                </Badge>
                <span className="text-muted-foreground">{t.tierBInline}</span>
              </li>
            ) : null}
            {mod.capabilities.map((cap) => (
              <li key={cap} className="flex items-center gap-2 text-sm">
                <Badge variant="outline" className="font-mono">
                  {cap}
                </Badge>
                <span className="text-muted-foreground">
                  {t.capabilityInfo[cap] ?? t.capabilityUnknown}
                </span>
              </li>
            ))}
            {!mod.tierB && mod.capabilities.length === 0 ? (
              <li className="text-sm text-muted-foreground">{t.noCapabilities}</li>
            ) : null}
          </ul>
        </section>

        <Separator />

        <section className="flex min-w-0 flex-col gap-2">
          <h3 className="font-mono text-xs tracking-wide text-muted-foreground uppercase">
            {t.versionInstallTitle}
          </h3>
          {version.status === 'loading' ? (
            <Skeleton className="h-[38px] w-full rounded-lg" />
          ) : version.status === 'success' ? (
            <div className="flex min-w-0 flex-col gap-3">
              <CommandBlock command={installCommand(version.data.url, mod.tierB)} />
              {version.data.sha256 ? (
                <div className="flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
                  <span className="min-w-0 truncate font-mono">
                    sha256:{version.data.sha256}
                  </span>
                  <CopyButton value={version.data.sha256} label={t.copySha256} size="icon-xs" />
                </div>
              ) : null}
            </div>
          ) : version.status === 'waiting' ? (
            <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
              <AlertTriangle className="size-3.5 shrink-0" />
              {version.data
                ? t.waitingForReleaseDetail(mod.sourceVersion, version.data.version)
                : t.waitingForRelease}
            </p>
          ) : (
            <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
              <AlertTriangle className="size-3.5 shrink-0" />
              {t.versionUnavailable}
            </p>
          )}
        </section>
      </div>

      <DialogFooter>
        <Button asChild variant="outline" size="sm">
          <a href={mod.docs[locale]}>
            <BookOpen data-icon="inline-start" />
            {t.moduleDocs}
          </a>
        </Button>
        <Button asChild variant="outline" size="sm">
          <a href={mod.repo} target="_blank" rel="noreferrer">
            <ExternalLink data-icon="inline-start" />
            {t.githubRepo}
          </a>
        </Button>
        <Button
          asChild
          size="sm"
          className={cn(version.status !== 'success' && 'pointer-events-none opacity-50')}
        >
          <a
            href={version.status === 'success' ? version.data.url : undefined}
            aria-disabled={version.status !== 'success'}
            tabIndex={version.status !== 'success' ? -1 : undefined}
          >
            <Download data-icon="inline-start" />
            {t.download}
          </a>
        </Button>
      </DialogFooter>
    </DialogContent>
  )
}

interface ModuleCardProps {
  module: RegistryModule
  version: VersionState
}

export function ModuleCard({ module: mod, version }: ModuleCardProps) {
  const { t, locale } = useI18n()
  return (
    <Dialog>
      <Card
        className={cn(
          'relative flex h-full flex-col transition-all duration-200 motion-reduce:transition-none',
          'hover:-translate-y-0.5 hover:ring-brand/40 hover:shadow-[0_12px_40px_-16px_color-mix(in_oklch,var(--brand)_45%,transparent)]',
          'has-[[data-slot=dialog-trigger]:focus-visible]:ring-2 has-[[data-slot=dialog-trigger]:focus-visible]:ring-ring/60',
          'motion-reduce:hover:translate-y-0',
        )}
      >
        {/* Stretched trigger: the whole card face opens the detail dialog. */}
        <DialogTrigger
          className="absolute inset-0 cursor-pointer rounded-xl outline-none"
          aria-label={t.viewDetails(mod.name[locale])}
        />

        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-2 text-lg">
            {mod.name[locale]}
            <VersionBadge version={version} />
          </CardTitle>
          {/* zh title pairs with the English name; en title pairs with the module id
            so the subtitle never duplicates the title. */}
          <CardDescription className="font-mono text-xs tracking-wide uppercase">
            {locale === 'zh_TW' ? mod.name.en_US : mod.id}
          </CardDescription>
          {mod.tierB ? (
            <CardAction className="relative z-10">
              <Tooltip>
                <TooltipTrigger asChild>
                  <Badge variant="destructive" className="gap-1">
                    <AlertTriangle data-icon="inline-start" />
                    Tier B
                  </Badge>
                </TooltipTrigger>
                <TooltipContent>{t.tierBWarning}</TooltipContent>
              </Tooltip>
            </CardAction>
          ) : null}
        </CardHeader>

        <CardContent className="flex flex-1 flex-col gap-4">
          <p className="text-sm text-muted-foreground">{mod.description[locale]}</p>

          <div className="flex flex-wrap gap-1.5">
            {mod.tierB ? <Badge variant="destructive">{t.tierBBadge}</Badge> : null}
            {mod.capabilities.map((cap) => (
              <Badge key={cap} variant="outline" className="font-mono">
                {cap}
              </Badge>
            ))}
          </div>

          {version.status === 'waiting' ? (
            <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <AlertTriangle className="size-3 shrink-0" />
              {t.waitingForRelease}
            </p>
          ) : version.status === 'error' ? (
            <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <AlertTriangle className="size-3 shrink-0" />
              {t.versionUnavailableShort}
            </p>
          ) : null}
        </CardContent>

        <CardFooter className="relative z-10 flex items-center justify-between gap-2">
          <Button asChild variant="ghost" size="sm" className="text-muted-foreground">
            <a href={mod.docs[locale]}>
              <BookOpen data-icon="inline-start" />
              {t.moduleDocs}
            </a>
          </Button>
          <Button
            asChild
            size="sm"
            className={cn(version.status !== 'success' && 'pointer-events-none opacity-50')}
          >
            <a
              href={version.status === 'success' ? version.data.url : undefined}
              aria-disabled={version.status !== 'success'}
              tabIndex={version.status !== 'success' ? -1 : undefined}
            >
              <Download data-icon="inline-start" />
              {t.download}
            </a>
          </Button>
        </CardFooter>
      </Card>

      <ModuleDetailDialog module={mod} version={version} />
    </Dialog>
  )
}

/** Loading placeholder mirroring the final card layout. */
export function ModuleCardSkeleton() {
  return (
    <Card aria-hidden="true" className="flex h-full flex-col">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Skeleton className="h-6 w-24" />
          <Skeleton className="h-5 w-14 rounded-full" />
        </CardTitle>
        <CardDescription>
          <Skeleton className="h-4 w-36" />
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-1 flex-col gap-4">
        <div className="flex flex-col gap-2">
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-4/5" />
        </div>
        <div className="flex gap-1.5">
          <Skeleton className="h-5 w-14 rounded-full" />
          <Skeleton className="h-5 w-16 rounded-full" />
        </div>
      </CardContent>
      <CardFooter className="flex items-center justify-between gap-2">
        <Skeleton className="h-7 w-20" />
        <Skeleton className="h-7 w-28" />
      </CardFooter>
    </Card>
  )
}
