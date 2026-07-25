import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { couriersApi } from '../../api/couriers'
import type { CourierCreate } from '../../types'
import { Dialog, DialogHeader, DialogTitle, DialogFooter } from '../ui/dialog'
import { Button } from '../ui/button'
import { Input } from '../ui/input'
import { Label } from '../ui/label'

const courierSchema = z.object({
  name: z.string().min(1, 'Обязательное поле'),
  phone: z.string().min(1, 'Обязательное поле'),
  password: z.string().min(6, 'Минимум 6 символов'),
})

type CourierForm = z.infer<typeof courierSchema>

interface AddCourierDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function AddCourierDialog({ open, onOpenChange }: AddCourierDialogProps) {
  const queryClient = useQueryClient()

  const { register, handleSubmit, reset, formState: { errors, isSubmitting } } = useForm<CourierForm>({
    resolver: zodResolver(courierSchema),
    defaultValues: { name: '', phone: '', password: '' },
  })

  const createMutation = useMutation({
    mutationFn: (data: CourierCreate) => couriersApi.create(data),
    onSuccess: () => {
      toast.success('Курьер добавлен')
      queryClient.invalidateQueries({ queryKey: ['couriers'] })
      queryClient.invalidateQueries({ queryKey: ['stats'] })
      reset()
      onOpenChange(false)
    },
    onError: (error: any) => {
      toast.error(error.response?.data?.detail || 'Ошибка добавления курьера')
    },
  })

  const onSubmit = (data: CourierForm) => {
    createMutation.mutate(data)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader>
        <DialogTitle>Добавить курьера</DialogTitle>
      </DialogHeader>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <Label htmlFor="name">Имя</Label>
          <Input id="name" {...register('name')} />
          {errors.name && <p className="text-sm text-red-500 mt-1">{errors.name.message}</p>}
        </div>
        <div>
          <Label htmlFor="phone">Телефон</Label>
          <Input id="phone" {...register('phone')} />
          {errors.phone && <p className="text-sm text-red-500 mt-1">{errors.phone.message}</p>}
        </div>
        <div>
          <Label htmlFor="password">Пароль</Label>
          <Input id="password" type="password" autoComplete="new-password" {...register('password')} />
          {errors.password && <p className="text-sm text-red-500 mt-1">{errors.password.message}</p>}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Отмена
          </Button>
          <Button type="submit" disabled={isSubmitting || createMutation.isPending}>
            {createMutation.isPending ? 'Добавление...' : 'Добавить'}
          </Button>
        </DialogFooter>
      </form>
    </Dialog>
  )
}
