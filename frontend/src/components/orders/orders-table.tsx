import type { Order } from '../../types'
import { statusConfig } from '../../types'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '../ui/table'
import { Button } from '../ui/button'
import { Ban, Trash2 } from 'lucide-react'

interface OrdersTableProps {
  orders: Order[]
  onCancelClick: (order: Order) => void
  onDeleteClick: (order: Order) => void
}

export function OrdersTable({ orders, onCancelClick, onDeleteClick }: OrdersTableProps) {
  if (orders.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-zinc-500">
        <p className="text-lg">Нет заказов</p>
        <p className="text-sm">Заказы появятся здесь после создания</p>
      </div>
    )
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>№ заказа</TableHead>
          <TableHead>Адрес</TableHead>
          <TableHead>Цена</TableHead>
          <TableHead>Курьеру</TableHead>
          <TableHead>Статус</TableHead>
          <TableHead>Телефон</TableHead>
          <TableHead className="text-right">Действия</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {orders.map((order) => {
          const s = statusConfig[order.status]
          return (
            <TableRow key={order.id}>
              <TableCell className="font-medium">{order.order_number}</TableCell>
              <TableCell className="max-w-[200px] truncate">{order.address}</TableCell>
              <TableCell>{order.price.toLocaleString()} ₽</TableCell>
              <TableCell>{order.courier_fee.toLocaleString()} ₽</TableCell>
              <TableCell>
                <span className={`inline-flex items-center rounded-md px-2.5 py-0.5 text-xs font-semibold ${s.color}`}>
                  {s.label}
                </span>
              </TableCell>
              <TableCell>{order.recipient_phone}</TableCell>
              <TableCell className="text-right">
                <div className="flex justify-end gap-1">
                  {order.status !== 'cancelled' && order.status !== 'delivered' && (
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => onCancelClick(order)}
                      title="Отменить"
                    >
                      <Ban className="h-4 w-4" />
                    </Button>
                  )}
                  {order.status === 'available' && (
                    <Button
                      variant="destructive"
                      size="icon"
                      onClick={() => onDeleteClick(order)}
                      title="Удалить"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  )
}