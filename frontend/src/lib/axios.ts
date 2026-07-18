import axios from 'axios'
import { useAuthStore } from '../stores/auth.store'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || '',
})

api.interceptors.request.use((config) => {
  const token = useAuthStore.getState().token
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      useAuthStore.getState().clearAuth()
      window.location.href = '/login'
    }
    return Promise.reject(error)
  },
)

export const wsUrl = () => {
  const token = useAuthStore.getState().token
  const base = import.meta.env.VITE_API_BASE_URL || ''
  const wsBase = base.replace(/^http/, 'ws')
  return `${wsBase}/ws/admin?token=${token}`
}

export default api