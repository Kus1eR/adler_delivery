import api from '../lib/axios'
import type { Order, OrderCreate, OrderUpdate, PaginatedOrders, Stats } from '../types'

export interface OrdersListParams {
  status?: string
  page?: number
  perPage?: number
  search?: string
}

export const ordersApi = {
  list: ({ perPage, ...params }: OrdersListParams = {}) =>
    api
      .get<PaginatedOrders>('/api/admin/orders', {
        params: { ...params, per_page: perPage },
      })
      .then((r) => r.data),

  exportCsv: (params: Pick<OrdersListParams, 'status' | 'search'> = {}) =>
    api
      .get<Blob>('/api/v1/admin/orders/export.csv', {
        params,
        responseType: 'blob',
      })
      .then((response) => response.data),

  stats: () =>
    api.get<Stats>('/api/admin/orders/stats').then((r) => r.data),

  create: (data: OrderCreate) =>
    api.post<Order>('/api/admin/orders', data).then((r) => r.data),

  update: (id: number, data: OrderUpdate) =>
    api.patch<Order>(`/api/admin/orders/${id}`, data).then((r) => r.data),

  cancel: (id: number, reason: string) =>
    api.patch(`/api/v1/admin/orders/${id}/cancel`, undefined, { params: { reason } }).then((r) => r.data),

  delete: (id: number) =>
    api.delete(`/api/admin/orders/${id}`).then((r) => r.data),
}
