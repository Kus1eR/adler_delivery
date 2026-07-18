import { Dialog, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../ui/dialog'
import { Button } from '../ui/button'

interface CancelOrderDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  orderNumber: string | null
  onConfirm: () => void
  isPending: boolean
}

export function CancelOrderDialog({
  open,
  onOpenChange,
  orderNumber,
  onConfirm,
  isPending,
}: CancelOrderDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader>
        <DialogTitle>Отменить заказ?</DialogTitle>
        <DialogDescription>
          {orderNumber
            ? `Вы уверены, что хотите отменить заказ ${orderNumber}?`
            : 'Вы уверены, что хотите отменить этот заказ?'}
        </DialogDescription>
      </DialogHeader>
      <DialogFooter>
        <Button variant="outline" onClick={() => onOpenChange(false)}>
          Назад
        </Button>
        <Button variant="destructive" onClick={onConfirm} disabled={isPending}>
          {isPending ? 'Отмена...' : 'Отменить заказ'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}