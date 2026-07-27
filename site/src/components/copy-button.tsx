import { useState } from 'react'
import { Check, Copy } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { useI18n } from '@/lib/i18n'
import { cn } from '@/lib/utils'

interface CopyButtonProps {
  value: string
  label?: string
  className?: string
  size?: 'icon' | 'icon-sm' | 'icon-xs'
}

export function CopyButton({ value, label, className, size = 'icon-sm' }: CopyButtonProps) {
  const { t } = useI18n()
  const [copied, setCopied] = useState(false)
  const copyLabel = label ?? t.copy

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(value)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      // Clipboard API unavailable (insecure context / permission denied) — no-op.
    }
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size={size}
          className={cn(
            'touch-manipulation text-muted-foreground hover:text-foreground pointer-coarse:size-10',
            className,
          )}
          onClick={handleCopy}
          aria-label={copyLabel}
        >
          {copied ? <Check className="text-live" /> : <Copy />}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{copied ? t.copied : copyLabel}</TooltipContent>
    </Tooltip>
  )
}
