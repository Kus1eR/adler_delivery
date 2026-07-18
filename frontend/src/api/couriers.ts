import api from '../lib/axios'
import type { Courier, CourierCreate } from '../types'

export const couriersApi = {
  list: () =>
    api.get<Courier[]>('/api/admin/couriers').then((r) => r.data),

  create: (data: CourierCreate) =>
    api.post<Courier>('/api/admin/couriers', data).then((r) => r.data),

  toggleBlock: (id: number) =>
    api.patch<Courier>(`/api/admin/couriers/${id}/block`).then((r) => r.data),
}