import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { z } from 'zod'
import { ordersApi } from '../../api/orders'
import type { Order } from '../../types'
import { Button } from '../ui/button'
import { Dialog, DialogFooter, DialogHeader, DialogTitle } from '../ui/dialog'
import { Input } from '../ui/input'
import { Label } from '../ui/label'

const orderUpdateSchema = z.object({
  order_number: z.string().min(1, 'Обязательное поле'),
  address: z.string().min(1, 'Обязательное поле'),
  price: z.number().positive('Должна быть больше 0'),
  courier_fee: z.number().min(0, 'Не может быть отрицательной'),
  description: z.string(),
  recipient_phone: z.string(),
  admin_phone: z.string(),
  latitude: z.number(),
  longitude: z.number(),
})

type OrderUpdateForm = z.infer<typeof orderUpdateSchema>

interface EditOrderDialogProps {
  order: Order | null
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EditOrderDialog({ order, open, onOpenChange }: EditOrderDialogProps) {
  const queryClient = useQueryClient()
  const { register, handleSubmit, reset, formState: { errors } } = useForm<OrderUpdateForm>({
    resolver: zodResolver(orderUpdateSchema),
  })

  useEffect(() => {
    if (!order) return
    reset({
      order_number: order.order_number,
      address: order.address,
      price: order.price,
      courier_fee: order.courier_fee,
      description: order.description ?? '',
      recipient_phone: order.recipient_phone,
      admin_phone: order.admin_phone,
      latitude: order.latitude,
      longitude: order.longitude,
    })
  }, [order, reset])

  const updateMutation = useMutation({
    mutationFn: (data: OrderUpdateForm) => ordersApi.update(order!.id, data),
    onSuccess: () => {
      toast.success('Заказ обновлён')
      queryClient.invalidateQueries({ queryKey: ['orders'] })
      onOpenChange(false)
    },
    onError: (error: { response?: { data?: { detail?: string } } }) => {
      toast.error(error.response?.data?.detail ?? 'Ошибка обновления заказа')
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader>
        <DialogTitle>Редактировать заказ</DialogTitle>
      </DialogHeader>
      <form onSubmit={handleSubmit((data) => updateMutation.mutate(data))} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label htmlFor="edit_order_number">Номер заказа</Label>
            <Input id="edit_order_number" {...register('order_number')} />
            {errors.order_number && <p className="mt-1 text-sm text-red-500">{errors.order_number.message}</p>}
          </div>
          <div>
            <Label htmlFor="edit_address">Адрес</Label>
            <Input id="edit_address" {...register('address')} />
            {errors.address && <p className="mt-1 text-sm text-red-500">{errors.address.message}</p>}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label htmlFor="edit_price">Цена (₽)</Label>
            <Input id="edit_price" type="number" step="0.01" {...register('price', { valueAsNumber: true })} />
            {errors.price && <p className="mt-1 text-sm text-red-500">{errors.price.message}</p>}
          </div>
          <div>
            <Label htmlFor="edit_courier_fee">Курьеру (₽)</Label>
            <Input id="edit_courier_fee" type="number" step="0.01" {...register('courier_fee', { valueAsNumber: true })} />
            {errors.courier_fee && <p className="mt-1 text-sm text-red-500">{errors.courier_fee.message}</p>}
          </div>
        </div>
        <div>
          <Label htmlFor="edit_description">Описание</Label>
          <Input id="edit_description" {...register('description')} />
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label htmlFor="edit_recipient_phone">Телефон получателя</Label>
            <Input id="edit_recipient_phone" {...register('recipient_phone')} />
          </div>
          <div>
            <Label htmlFor="edit_admin_phone">Телефон админа</Label>
            <Input id="edit_admin_phone" {...register('admin_phone')} />
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Label htmlFor="edit_latitude">Широта</Label>
            <Input id="edit_latitude" type="number" step="any" {...register('latitude', { valueAsNumber: true })} />
          </div>
          <div>
            <Label htmlFor="edit_longitude">Долгота</Label>
            <Input id="edit_longitude" type="number" step="any" {...register('longitude', { valueAsNumber: true })} />
          </div>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Отмена
          </Button>
          <Button type="submit" disabled={updateMutation.isPending}>
            {updateMutation.isPending ? 'Сохранение...' : 'Сохранить'}
          </Button>
        </DialogFooter>
      </form>
    </Dialog>
  )
}
