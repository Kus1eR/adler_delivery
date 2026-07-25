import { useEffect, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { ordersApi } from '../api/orders'
import { StatusFilter } from '../components/orders/status-filter'
import { OrdersTable } from '../components/orders/orders-table'
import { CreateOrderDialog } from '../components/orders/create-dialog'
import { CancelOrderDialog } from '../components/orders/cancel-dialog'
import { DeleteOrderDialog } from '../components/orders/delete-dialog'
import { EditOrderDialog } from '../components/orders/edit-dialog'
import { Button } from '../components/ui/button'
import { Input } from '../components/ui/input'
import { Download, Plus, RotateCw, Search } from 'lucide-react'
import type { Order } from '../types'

export default function OrdersPage() {
  const queryClient = useQueryClient()
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [searchInput, setSearchInput] = useState('')
  const [search, setSearch] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [cancelOrder, setCancelOrder] = useState<Order | null>(null)
  const [deleteOrder, setDeleteOrder] = useState<Order | null>(null)
  const [editOrder, setEditOrder] = useState<Order | null>(null)
  const [isExporting, setIsExporting] = useState(false)

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['orders', statusFilter, page, search],
    queryFn: () => ordersApi.list({
      status: statusFilter || undefined,
      page,
      perPage: 20,
      search: search || undefined,
    }),
  })

  const orders = data?.items ?? []
  const total = data?.total ?? 0
  const pages = data?.pages ?? 0

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setSearch(searchInput.trim())
      setPage(1)
    }, 300)
    return () => window.clearTimeout(timer)
  }, [searchInput])

  useEffect(() => {
    if (data && page > Math.max(data.pages, 1)) {
      setPage(Math.max(data.pages, 1))
    }
  }, [data, page])

  const cancelMutation = useMutation({
    mutationFn: ({ id, reason }: { id: number; reason: string }) => ordersApi.cancel(id, reason),
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

  const handleClearSearch = () => {
    setSearchInput('')
  }

  const handleExport = async () => {
    setIsExporting(true)
    try {
      const blob = await ordersApi.exportCsv({
        status: statusFilter || undefined,
        search: search || undefined,
      })
      const url = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      link.download = `orders-${new Date().toISOString().slice(0, 10)}.csv`
      link.click()
      URL.revokeObjectURL(url)
    } catch {
      toast.error('Ошибка экспорта заказов')
    } finally {
      setIsExporting(false)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Заказы</h2>
        <div className="flex gap-2">
          <Button variant="outline" onClick={handleExport} disabled={isExporting}>
            <Download className="mr-2 h-4 w-4" />
            {isExporting ? 'Экспорт...' : 'CSV'}
          </Button>
          <Button variant="outline" size="icon" onClick={() => refetch()}>
            <span className="sr-only">Обновить заказы</span>
            <RotateCw className="h-4 w-4" />
          </Button>
          <Button onClick={() => setCreateOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Создать заказ
          </Button>
        </div>
      </div>

      <div className="flex items-center gap-2 mb-4">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            aria-label="Поиск заказов"
            placeholder="Поиск по номеру или адресу..."
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            className="pl-9"
          />
        </div>
        {searchInput && (
          <Button variant="ghost" size="sm" onClick={handleClearSearch}>
            Сбросить
          </Button>
        )}
      </div>

      <StatusFilter value={statusFilter} onChange={(v) => { setStatusFilter(v); setPage(1) }} />

      {isLoading ? (
        <div className="flex items-center justify-center py-12 text-zinc-500">
          Загрузка...
        </div>
      ) : (
        <>
          <OrdersTable
            orders={orders}
            onEditClick={(o) => setEditOrder(o)}
            onCancelClick={(o) => setCancelOrder(o)}
            onDeleteClick={(o) => setDeleteOrder(o)}
          />

          <div className="flex items-center justify-between mt-4">
            <div className="text-sm text-muted-foreground">
              Всего: {total} | Стр. {page} из {Math.max(pages, 1)}
            </div>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
              >
                Назад
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={page >= pages}
                onClick={() => setPage((p) => p + 1)}
              >
                Вперёд
              </Button>
            </div>
          </div>
        </>
      )}

      <CreateOrderDialog open={createOpen} onOpenChange={setCreateOpen} />

      <EditOrderDialog
        order={editOrder}
        open={editOrder !== null}
        onOpenChange={(open) => !open && setEditOrder(null)}
      />

      <CancelOrderDialog
        open={cancelOrder !== null}
        onOpenChange={(open) => !open && setCancelOrder(null)}
        orderNumber={cancelOrder?.order_number ?? null}
        onConfirm={(reason) => cancelOrder && cancelMutation.mutate({ id: cancelOrder.id, reason })}
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
