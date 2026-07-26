import { CopyButton } from '@/components/copy-button'

interface CommandBlockProps {
  command: string
  label?: string
}

export function CommandBlock({ command, label }: CommandBlockProps) {
  return (
    <div className="flex flex-col gap-1.5">
      {label ? <span className="text-xs text-muted-foreground">{label}</span> : null}
      <div className="flex items-center gap-2 rounded-lg border border-border bg-card/60 py-2 pr-1.5 pl-4">
        <code className="flex-1 overflow-x-auto font-mono text-sm text-foreground/90 whitespace-pre">
          {command}
        </code>
        <CopyButton value={command} label="複製指令" />
      </div>
    </div>
  )
}
