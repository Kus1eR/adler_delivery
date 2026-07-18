import api from '../lib/axios'
import type { CourierLocation } from '../types'

export const locationsApi = {
  get: () =>
    api.get<CourierLocation[]>('/api/admin/couriers/locations').then((r) => r.data),
}