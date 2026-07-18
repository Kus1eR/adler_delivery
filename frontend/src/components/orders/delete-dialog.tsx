import { Dialog, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../ui/dialog'
import { Button } from '../ui/button'

interface DeleteOrderDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  orderNumber: string | null
  onConfirm: () => void
  isDeleting: boolean
}

export function DeleteOrderDialog({
  open,
  onOpenChange,
  orderNumber,
  onConfirm,
  isDeleting,
}: DeleteOrderDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader>
        <DialogTitle>Удалить заказ?</DialogTitle>
        <DialogDescription>
          {orderNumber
            ? `Вы уверены, что хотите удалить заказ ${orderNumber}? Это действие нельзя отменить.`
            : 'Вы уверены, что хотите удалить этот заказ? Это действие нельзя отменить.'}
        </DialogDescription>
      </DialogHeader>
      <DialogFooter>
        <Button variant="outline" onClick={() => onOpenChange(false)}>
          Отмена
        </Button>
        <Button variant="destructive" onClick={onConfirm} disabled={isDeleting}>
          {isDeleting ? 'Удаление...' : 'Удалить'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}