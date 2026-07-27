import { CopyButton } from '@/components/copy-button'
import { useI18n } from '@/lib/i18n'

interface CommandBlockProps {
  command: string
  label?: string
}

export function CommandBlock({ command, label }: CommandBlockProps) {
  const { t } = useI18n()
  return (
    <div className="min-w-0 flex flex-col gap-1.5">
      {label ? <span className="text-xs text-muted-foreground">{label}</span> : null}
      {/* The pill hugs the command's natural width on wide screens (sm:w-fit);
          when the container is narrower than the command, the text wraps —
          never truncates, never scrolls. */}
      <div className="flex w-full max-w-full items-start gap-2 rounded-lg border border-border bg-card/60 py-2 pr-1.5 pl-3.5 sm:w-fit">
        <span
          aria-hidden="true"
          className="font-mono text-xs leading-5 text-brand select-none"
        >
          $
        </span>
        <code className="min-w-0 flex-1 font-mono text-xs leading-5 whitespace-pre-wrap [overflow-wrap:anywhere] text-foreground/90">
          {command}
        </code>
        {/* -my-1 centers the 28px button on the 20px first text line. */}
        <CopyButton value={command} label={t.copyCommand} className="-my-1" />
      </div>
    </div>
  )
}
