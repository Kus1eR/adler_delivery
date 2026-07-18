import api from '../lib/axios'
import type { LoginRequest, LoginResponse } from '../types'

export const authApi = {
  login: (data: LoginRequest) =>
    api.post<LoginResponse>('/api/admin/login', data).then((r) => r.data),
}