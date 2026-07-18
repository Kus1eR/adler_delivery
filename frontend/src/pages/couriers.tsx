import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { couriersApi } from '../api/couriers'
import { CouriersTable } from '../components/couriers/couriers-table'
import { AddCourierDialog } from '../components/couriers/add-dialog'
import { Dialog, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../components/ui/dialog'
import { Button } from '../components/ui/button'
import { Plus, RotateCw } from 'lucide-react'
import type { Courier } from '../types'

export default function CouriersPage() {
  const queryClient = useQueryClient()
  const [addOpen, setAddOpen] = useState(false)
  const [toggleCourier, setToggleCourier] = useState<Courier | null>(null)

  const { data: couriers = [], isLoading, refetch } = useQuery({
    queryKey: ['couriers'],
    queryFn: couriersApi.list,
  })

  const toggleMutation = useMutation({
    mutationFn: (id: number) => couriersApi.toggleBlock(id),
    onSuccess: () => {
      toast.success('Статус обновлён')
      queryClient.invalidateQueries({ queryKey: ['couriers'] })
      queryClient.invalidateQueries({ queryKey: ['stats'] })
      setToggleCourier(null)
    },
    onError: () => toast.error('Ошибка обновления статуса'),
  })

  const handleToggleBlock = (courier: Courier) => {
    setToggleCourier(courier)
  }

  const confirmToggle = () => {
    if (toggleCourier) {
      toggleMutation.mutate(toggleCourier.id)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Курьеры</h2>
        <div className="flex gap-2">
          <Button variant="outline" size="icon" onClick={() => refetch()}>
            <RotateCw className="h-4 w-4" />
          </Button>
          <Button onClick={() => setAddOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Добавить курьера
          </Button>
        </div>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-12 text-zinc-500">
          Загрузка...
        </div>
      ) : (
        <CouriersTable couriers={couriers} onToggleBlock={handleToggleBlock} />
      )}

      <AddCourierDialog open={addOpen} onOpenChange={setAddOpen} />

      <Dialog open={toggleCourier !== null} onOpenChange={(open) => !open && setToggleCourier(null)}>
        <DialogHeader>
          <DialogTitle>
            {toggleCourier?.status === 'blocked' ? 'Разблокировать' : 'Заблокировать'} курьера?
          </DialogTitle>
          <DialogDescription>
            {toggleCourier
              ? `Вы уверены, что хотите ${toggleCourier.status === 'blocked' ? 'разблокировать' : 'заблокировать'} курьера ${toggleCourier.name}?`
              : ''}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => setToggleCourier(null)}>
            Отмена
          </Button>
          <Button
            variant={toggleCourier?.status === 'blocked' ? 'default' : 'destructive'}
            onClick={confirmToggle}
            disabled={toggleMutation.isPending}
          >
            {toggleMutation.isPending
              ? 'Обновление...'
              : toggleCourier?.status === 'blocked'
                ? 'Разблокировать'
                : 'Заблокировать'}
          </Button>
        </DialogFooter>
      </Dialog>
    </div>
  )
}