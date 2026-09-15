'use client'

import { useState } from 'react'
import { Check, Copy } from 'lucide-react'
import { Button } from '@/components/ui/button'

export function CopyField({ value, label }: { value: string; label?: string }) {
  const [copied, setCopied] = useState(false)

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value)
    } catch {
      // fallback for non-secure contexts
      const ta = document.createElement('textarea')
      ta.value = value
      document.body.appendChild(ta)
      ta.select()
      document.execCommand('copy')
      document.body.removeChild(ta)
    }
    setCopied(true)
    setTimeout(() => setCopied(false), 1800)
  }

  return (
    <div className="flex w-full items-stretch gap-2">
      <div className="min-w-0 flex-1 overflow-hidden rounded-lg border border-white/10 bg-black/40 px-3 py-2">
        {label && (
          <div className="mb-0.5 text-[10px] font-medium uppercase tracking-wider text-zinc-500">
            {label}
          </div>
        )}
        <code className="block truncate font-mono text-xs text-zinc-300" title={value}>
          {value}
        </code>
      </div>
      <Button
        variant="outline"
        size="icon"
        onClick={copy}
        aria-label={copied ? 'Copied' : 'Copy checksum'}
        className="shrink-0 border-white/10 bg-white/5 text-zinc-300 hover:bg-white/10 hover:text-cyan-300"
      >
        {copied ? <Check className="h-4 w-4 text-emerald-400" /> : <Copy className="h-4 w-4" />}
      </Button>
    </div>
  )
}
