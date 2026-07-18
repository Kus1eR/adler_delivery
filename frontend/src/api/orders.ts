import api from '../lib/axios'
import type { Order, OrderCreate, Stats } from '../types'

export const ordersApi = {
  list: (status?: string) =>
    api
      .get<Order[]>('/api/admin/orders', { params: status ? { status } : {} })
      .then((r) => r.data),

  stats: () =>
    api.get<Stats>('/api/admin/orders/stats').then((r) => r.data),

  create: (data: OrderCreate) =>
    api.post<Order>('/api/admin/orders', data).then((r) => r.data),

  cancel: (id: number) =>
    api.patch(`/api/admin/orders/${id}/cancel`).then((r) => r.data),

  delete: (id: number) =>
    api.delete(`/api/admin/orders/${id}`).then((r) => r.data),
}