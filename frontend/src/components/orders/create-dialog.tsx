import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { ordersApi } from '../../api/orders'
import { Dialog, DialogHeader, DialogTitle, DialogFooter } from '../ui/dialog'
import { Button } from '../ui/button'
import { Input } from '../ui/input'
import { Label } from '../ui/label'

const orderSchema = z.object({
  order_number: z.string().min(1, 'Обязательное поле'),
  address: z.string().min(1, 'Обязательное поле'),
  price: z.coerce.number().positive('Должна быть больше 0'),
  courier_fee: z.coerce.number().min(0, 'Не может быть отрицательной'),
  description: z.string().optional(),
  recipient_phone: z.string().min(1, 'Обязательное поле'),
  admin_phone: z.string().min(1, 'Обязательное поле'),
})

interface CreateOrderDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function CreateOrderDialog({ open, onOpenChange }: CreateOrderDialogProps) {
  const queryClient = useQueryClient()

  const { register, handleSubmit, reset, formState: { errors, isSubmitting } } = useForm({
    resolver: zodResolver(orderSchema),
    defaultValues: {
      order_number: '',
      address: '',
      price: 0,
      courier_fee: 0,
      description: '',
      recipient_phone: '',
      admin_phone: '+79000000000',
    },
  })

  const createMutation = useMutation({
    mutationFn: ordersApi.create,
    onSuccess: () => {
      toast.success('Заказ создан')
      queryClient.invalidateQueries({ queryKey: ['orders'] })
      queryClient.invalidateQueries({ queryKey: ['stats'] })
      reset()
      onOpenChange(false)
    },
    onError: (error: { response?: { data?: { detail?: string } } }) => {
      toast.error(error.response?.data?.detail ?? 'Ошибка создания заказа')
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader>
        <DialogTitle>Создать заказ</DialogTitle>
      </DialogHeader>
      <form onSubmit={handleSubmit((data) => createMutation.mutate(data))} className="space-y-4">
        <div>
          <Label htmlFor="order_number">Номер заказа</Label>
          <Input id="order_number" {...register('order_number')} />
          {errors.order_number && <p className="text-sm text-red-500 mt-1">{errors.order_number.message}</p>}
        </div>
        <div>
          <Label htmlFor="address">Адрес</Label>
          <Input id="address" {...register('address')} />
          {errors.address && <p className="text-sm text-red-500 mt-1">{errors.address.message}</p>}
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label htmlFor="price">Цена (₽)</Label>
            <Input id="price" type="number" step="0.01" {...register('price', { valueAsNumber: true })} />
            {errors.price && <p className="text-sm text-red-500 mt-1">{errors.price.message}</p>}
          </div>
          <div>
            <Label htmlFor="courier_fee">Курьеру (₽)</Label>
            <Input id="courier_fee" type="number" step="0.01" {...register('courier_fee', { valueAsNumber: true })} />
            {errors.courier_fee && <p className="text-sm text-red-500 mt-1">{errors.courier_fee.message}</p>}
          </div>
        </div>
        <div>
          <Label htmlFor="description">Описание</Label>
          <Input id="description" {...register('description')} />
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label htmlFor="recipient_phone">Телефон получателя</Label>
            <Input id="recipient_phone" {...register('recipient_phone')} />
            {errors.recipient_phone && <p className="text-sm text-red-500 mt-1">{errors.recipient_phone.message}</p>}
          </div>
          <div>
            <Label htmlFor="admin_phone">Телефон админа</Label>
            <Input id="admin_phone" {...register('admin_phone')} />
            {errors.admin_phone && <p className="text-sm text-red-500 mt-1">{errors.admin_phone.message}</p>}
          </div>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Отмена
          </Button>
          <Button type="submit" disabled={isSubmitting || createMutation.isPending}>
            {createMutation.isPending ? 'Создание...' : 'Создать'}
          </Button>
        </DialogFooter>
      </form>
    </Dialog>
  )
}