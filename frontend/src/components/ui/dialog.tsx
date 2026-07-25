import { useEffect, useRef } from 'react'
import { cn } from '../../lib/utils'

interface DialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  children: React.ReactNode
}

function Dialog({ open, onOpenChange, children }: DialogProps) {
  const dialogRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!open) return
    const previousFocus = document.activeElement as HTMLElement | null
    const focusable = () => Array.from(dialogRef.current?.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [href], [tabindex]:not([tabindex="-1"])',
    ) ?? [])
    ;(focusable()[0] ?? dialogRef.current)?.focus()
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onOpenChange(false)
      if (event.key !== 'Tab') return
      const items = focusable()
      if (items.length === 0) {
        event.preventDefault()
        return
      }
      const first = items[0]
      const last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('keydown', onKeyDown)
      previousFocus?.focus()
    }
  }, [onOpenChange, open])
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div
        className="fixed inset-0 bg-black/50 dark:bg-black/80"
        onClick={() => onOpenChange(false)}
      />
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label="Диалог"
        tabIndex={-1}
        className="relative z-50 w-full max-w-lg rounded-lg border border-zinc-200 bg-white p-6 shadow-lg dark:border-zinc-800 dark:bg-zinc-950"
      >
        {children}
      </div>
    </div>
  )
}

function DialogHeader({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('mb-4', className)} {...props} />
}

function DialogTitle({ className, ...props }: React.HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn('text-lg font-semibold', className)} {...props} />
}

function DialogDescription({ className, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn('text-sm text-zinc-500 dark:text-zinc-400', className)} {...props} />
}

function DialogFooter({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn('mt-6 flex justify-end gap-2', className)}
      {...props}
    />
  )
}

export { Dialog, DialogHeader, DialogTitle, DialogDescription, DialogFooter }
