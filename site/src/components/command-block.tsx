import { CopyButton } from '@/components/copy-button'

interface CommandBlockProps {
  command: string
  label?: string
}

export function CommandBlock({ command, label }: CommandBlockProps) {
  return (
    <div className="min-w-0 flex flex-col gap-1.5">
      {label ? <span className="text-xs text-muted-foreground">{label}</span> : null}
      <div className="flex items-center gap-2 rounded-lg border border-border bg-card/60 py-2 pr-1.5 pl-3.5">
        <span aria-hidden="true" className="font-mono text-xs text-brand select-none sm:text-sm">
          $
        </span>
        <code className="min-w-0 flex-1 overflow-x-auto overscroll-x-contain font-mono text-xs whitespace-pre text-foreground/90 sm:text-sm">
          {command}
        </code>
        <CopyButton value={command} label="複製指令" />
      </div>
    </div>
  )
}
