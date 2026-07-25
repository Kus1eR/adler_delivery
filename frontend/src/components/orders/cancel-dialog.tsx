import { useEffect, useState } from 'react'
import { Dialog, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../ui/dialog'
import { Button } from '../ui/button'

interface CancelOrderDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  orderNumber: string | null
  onConfirm: (reason: string) => void
  isPending: boolean
}

export function CancelOrderDialog({
  open,
  onOpenChange,
  orderNumber,
  onConfirm,
  isPending,
}: CancelOrderDialogProps) {
  const [reason, setReason] = useState('')
  const trimmedReason = reason.trim()
  const isValid = trimmedReason.length >= 3 && trimmedReason.length <= 500

  useEffect(() => {
    if (!open) setReason('')
  }, [open])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader>
        <DialogTitle>Отменить заказ?</DialogTitle>
        <DialogDescription>
          {orderNumber
            ? `Вы уверены, что хотите отменить заказ ${orderNumber}?`
            : 'Вы уверены, что хотите отменить этот заказ?'}
        </DialogDescription>
        <label className="mt-4 block text-sm font-medium" htmlFor="cancel-reason">
          Причина отмены
        </label>
        <textarea
          id="cancel-reason"
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          minLength={3}
          maxLength={500}
          rows={4}
          required
          className="mt-2 w-full resize-y rounded-md border border-zinc-300 bg-transparent px-3 py-2 text-sm outline-none focus:border-zinc-500 dark:border-zinc-700"
          placeholder="От 3 до 500 символов"
        />
        <p className="mt-1 text-xs text-zinc-500">{reason.length}/500</p>
      </DialogHeader>
      <DialogFooter>
        <Button variant="outline" onClick={() => onOpenChange(false)}>
          Назад
        </Button>
        <Button
          variant="destructive"
          onClick={() => onConfirm(trimmedReason)}
          disabled={isPending || !isValid}
        >
          {isPending ? 'Отмена...' : 'Отменить заказ'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}
