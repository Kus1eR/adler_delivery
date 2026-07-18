import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { ordersApi } from '../api/orders'
import { StatusFilter } from '../components/orders/status-filter'
import { OrdersTable } from '../components/orders/orders-table'
import { CreateOrderDialog } from '../components/orders/create-dialog'
import { CancelOrderDialog } from '../components/orders/cancel-dialog'
import { DeleteOrderDialog } from '../components/orders/delete-dialog'
import { Button } from '../components/ui/button'
import { Plus, RotateCw } from 'lucide-react'
import type { Order } from '../types'

export default function OrdersPage() {
  const queryClient = useQueryClient()
  const [statusFilter, setStatusFilter] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [cancelOrder, setCancelOrder] = useState<Order | null>(null)
  const [deleteOrder, setDeleteOrder] = useState<Order | null>(null)

  const { data: orders = [], isLoading, refetch } = useQuery({
    queryKey: ['orders', statusFilter],
    queryFn: () => ordersApi.list(statusFilter || undefined),
  })

  const cancelMutation = useMutation({
    mutationFn: (id: number) => ordersApi.cancel(id),
    onSuccess: () => {
      toast.success('Заказ отменён')
      queryClient.invalidateQueries({ queryKey: ['orders'] })
      queryClient.invalidateQueries({ queryKey: ['stats'] })
      setCancelOrder(null)
    },
    onError: () => toast.error('Ошибка отмены заказа'),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => ordersApi.delete(id),
    onSuccess: () => {
      toast.success('Заказ удалён')
      queryClient.invalidateQueries({ queryKey: ['orders'] })
      queryClient.invalidateQueries({ queryKey: ['stats'] })
      setDeleteOrder(null)
    },
    onError: () => toast.error('Ошибка удаления заказа'),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Заказы</h2>
        <div className="flex gap-2">
          <Button variant="outline" size="icon" onClick={() => refetch()}>
            <RotateCw className="h-4 w-4" />
          </Button>
          <Button onClick={() => setCreateOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Создать заказ
          </Button>
        </div>
      </div>

      <StatusFilter value={statusFilter} onChange={setStatusFilter} />

      {isLoading ? (
        <div className="flex items-center justify-center py-12 text-zinc-500">
          Загрузка...
        </div>
      ) : (
        <OrdersTable
          orders={orders}
          onCancelClick={(o) => setCancelOrder(o)}
          onDeleteClick={(o) => setDeleteOrder(o)}
        />
      )}

      <CreateOrderDialog open={createOpen} onOpenChange={setCreateOpen} />

      <CancelOrderDialog
        open={cancelOrder !== null}
        onOpenChange={(open) => !open && setCancelOrder(null)}
        orderNumber={cancelOrder?.order_number ?? null}
        onConfirm={() => cancelOrder && cancelMutation.mutate(cancelOrder.id)}
        isPending={cancelMutation.isPending}
      />

      <DeleteOrderDialog
        open={deleteOrder !== null}
        onOpenChange={(open) => !open && setDeleteOrder(null)}
        orderNumber={deleteOrder?.order_number ?? null}
        onConfirm={() => deleteOrder && deleteMutation.mutate(deleteOrder.id)}
        isDeleting={deleteMutation.isPending}
      />
    </div>
  )
}