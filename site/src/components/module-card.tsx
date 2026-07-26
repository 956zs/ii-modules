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
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { CopyButton } from '@/components/copy-button'
import { cn } from '@/lib/utils'
import type { RegistryModule, VersionState } from '@/lib/types'

function truncateSha(sha: string): string {
  if (sha.length <= 14) return sha
  return `${sha.slice(0, 8)}…${sha.slice(-6)}`
}

interface ModuleCardProps {
  module: RegistryModule
  version: VersionState
}

export function ModuleCard({ module: mod, version }: ModuleCardProps) {
  return (
    <Card className="flex h-full flex-col">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-lg">
          {mod.name.zh_TW}
          {version.status === 'loading' ? (
            <Skeleton className="h-5 w-14 rounded-full" />
          ) : version.status === 'success' ? (
            <Badge
              variant="secondary"
              className="gap-1.5 font-mono text-[0.7rem]"
            >
              <span className="relative flex size-1.5">
                <span className="absolute inline-flex size-full rounded-full bg-live animate-live-breathe" />
              </span>
              v{version.data.version}
            </Badge>
          ) : (
            <Badge variant="outline" className="text-[0.7rem] text-muted-foreground">
              版本未知
            </Badge>
          )}
        </CardTitle>
        <CardDescription className="font-mono text-xs tracking-wide uppercase">
          {mod.name.en_US}
        </CardDescription>
        {mod.tierB ? (
          <CardAction>
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
          {mod.tierB ? (
            <Badge variant="destructive">修改 stock 檔</Badge>
          ) : null}
          {mod.capabilities.map((cap) => (
            <Badge key={cap} variant="outline" className="font-mono">
              {cap}
            </Badge>
          ))}
        </div>

        {version.status === 'success' && version.data.sha256 ? (
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <span className="font-mono">sha256:{truncateSha(version.data.sha256)}</span>
            <CopyButton value={version.data.sha256} label="複製 sha256" size="icon-xs" />
          </div>
        ) : null}

        {version.status === 'error' ? (
          <p className="text-xs text-muted-foreground italic">版本資訊暫時無法取得</p>
        ) : null}
      </CardContent>

      <CardFooter className="flex items-center justify-between gap-2">
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
  )
}
