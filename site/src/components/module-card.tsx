import { AlertTriangle, Download, ExternalLink } from 'lucide-react'
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
import { cn } from '@/lib/utils'
import type { RegistryModule, VersionState } from '@/lib/types'

/** Plain-language explanations for the SPEC §6 capability declarations. */
const CAPABILITY_INFO: Record<string, string> = {
  exec: '會執行外部程式',
  network: '會進行網路連線',
  'filesystem-write': '會寫入自身設定以外的檔案',
  dbus: '會存取 D-Bus 系統服務',
}

function VersionBadge({ version }: { version: VersionState }) {
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
  return (
    <Badge variant="outline" className="text-[0.7rem] text-muted-foreground">
      版本未知
    </Badge>
  )
}

function ModuleDetailDialog({ module: mod, version }: ModuleCardProps) {
  // Wide enough that the install command rarely wraps on desktop (w-fit would
  // break here: shrink-to-fit of a fixed element with left:50% caps available
  // width at half the viewport).
  return (
    <DialogContent className="max-h-[85svh] grid-cols-1 overflow-x-hidden overflow-y-auto *:min-w-0 sm:max-w-[min(92vw,60rem)]">
      <DialogHeader>
        <DialogTitle className="flex flex-wrap items-center gap-2 pr-8 text-lg">
          {mod.name.zh_TW}
          <VersionBadge version={version} />
        </DialogTitle>
        <DialogDescription className="font-mono text-xs tracking-wide uppercase">
          {mod.name.en_US}
        </DialogDescription>
      </DialogHeader>

      <div className="flex min-w-0 flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <p className="text-sm text-foreground/90">{mod.description.zh_TW}</p>
          <p className="text-sm text-muted-foreground">{mod.description.en_US}</p>
        </div>

        <Separator />

        <section className="flex flex-col gap-2">
          <h3 className="font-mono text-xs tracking-wide text-muted-foreground uppercase">
            權限與能力
          </h3>
          <ul className="flex flex-col gap-1.5">
            {mod.tierB ? (
              <li className="flex items-center gap-2 text-sm">
                <Badge variant="destructive" className="gap-1">
                  <AlertTriangle data-icon="inline-start" />
                  Tier B
                </Badge>
                <span className="text-muted-foreground">會修改 stock 檔，安裝前請詳閱說明</span>
              </li>
            ) : null}
            {mod.capabilities.map((cap) => (
              <li key={cap} className="flex items-center gap-2 text-sm">
                <Badge variant="outline" className="font-mono">
                  {cap}
                </Badge>
                <span className="text-muted-foreground">{CAPABILITY_INFO[cap] ?? '未知能力'}</span>
              </li>
            ))}
            {!mod.tierB && mod.capabilities.length === 0 ? (
              <li className="text-sm text-muted-foreground">不需要任何特殊能力。</li>
            ) : null}
          </ul>
        </section>

        <Separator />

        <section className="flex min-w-0 flex-col gap-2">
          <h3 className="font-mono text-xs tracking-wide text-muted-foreground uppercase">
            版本與安裝
          </h3>
          {version.status === 'loading' ? (
            <Skeleton className="h-[38px] w-full rounded-lg" />
          ) : version.status === 'success' ? (
            <div className="flex min-w-0 flex-col gap-3">
              <CommandBlock command={`iimod install ${version.data.url}`} />
              {version.data.sha256 ? (
                <div className="flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
                  <span className="min-w-0 truncate font-mono">
                    sha256:{version.data.sha256}
                  </span>
                  <CopyButton value={version.data.sha256} label="複製 sha256" size="icon-xs" />
                </div>
              ) : null}
            </div>
          ) : (
            <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
              <AlertTriangle className="size-3.5 shrink-0" />
              版本資訊暫時無法取得，請稍後再試。
            </p>
          )}
        </section>
      </div>

      <DialogFooter>
        <Button asChild variant="outline" size="sm">
          <a href={mod.repo} target="_blank" rel="noreferrer">
            <ExternalLink data-icon="inline-start" />
            GitHub Repo
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
            下載 .iimod
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
          aria-label={`查看「${mod.name.zh_TW}」詳細資訊`}
        />

        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-2 text-lg">
            {mod.name.zh_TW}
            <VersionBadge version={version} />
          </CardTitle>
          <CardDescription className="font-mono text-xs tracking-wide uppercase">
            {mod.name.en_US}
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
                <TooltipContent>此模塊會修改 stock 檔，安裝前請詳閱說明</TooltipContent>
              </Tooltip>
            </CardAction>
          ) : null}
        </CardHeader>

        <CardContent className="flex flex-1 flex-col gap-4">
          <p className="text-sm text-muted-foreground">{mod.description.zh_TW}</p>

          <div className="flex flex-wrap gap-1.5">
            {mod.tierB ? <Badge variant="destructive">修改 stock 檔</Badge> : null}
            {mod.capabilities.map((cap) => (
              <Badge key={cap} variant="outline" className="font-mono">
                {cap}
              </Badge>
            ))}
          </div>

          {version.status === 'error' ? (
            <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <AlertTriangle className="size-3 shrink-0" />
              版本資訊暫時無法取得
            </p>
          ) : null}
        </CardContent>

        <CardFooter className="relative z-10 flex items-center justify-between gap-2">
          <Button asChild variant="ghost" size="sm" className="text-muted-foreground">
            <a href={mod.repo} target="_blank" rel="noreferrer">
              <ExternalLink data-icon="inline-start" />
              Repo
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
              下載 .iimod
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
