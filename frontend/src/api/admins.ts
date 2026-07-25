import api from '../lib/axios'
import type { Admin, AdminCreate } from '../types'

export const adminsApi = {
  me: () => api.get<Admin>('/api/v1/admin/me').then((response) => response.data),

  list: () =>
    api.get<Admin[]>('/api/v1/admin/admins').then((response) => response.data),

  create: (data: AdminCreate) =>
    api.post<Admin>('/api/v1/admin/admins', data).then((response) => response.data),

  setActive: (id: number, isActive: boolean) =>
    api
      .patch<Admin>(`/api/v1/admin/admins/${id}/status`, { is_active: isActive })
      .then((response) => response.data),
}
