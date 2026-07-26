import { useState } from 'react'
import { Check, Copy } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { cn } from '@/lib/utils'

interface CopyButtonProps {
  value: string
  label?: string
  className?: string
  size?: 'icon' | 'icon-sm' | 'icon-xs'
}

export function CopyButton({ value, label = '複製', className, size = 'icon-sm' }: CopyButtonProps) {
  const [copied, setCopied] = useState(false)

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
          className={cn('text-muted-foreground hover:text-foreground', className)}
          onClick={handleCopy}
          aria-label={label}
        >
          {copied ? <Check className="text-live" /> : <Copy />}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{copied ? '已複製' : label}</TooltipContent>
    </Tooltip>
  )
}
