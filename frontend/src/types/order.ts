import type { Courier } from './courier'

export type OrderStatus = 'available' | 'taken' | 'in_transit' | 'delivered' | 'cancelled'

export interface Order {
  id: number
  order_number: string
  address: string
  price: number
  courier_fee: number
  description: string | null
  recipient_phone: string
  admin_phone: string
  status: OrderStatus
  courier_id: number | null
  courier: Courier | null
  latitude: number
  longitude: number
  created_at: string
  updated_at: string
}

export interface OrderCreate {
  order_number: string
  address: string
  price: number
  courier_fee: number
  description?: string
  recipient_phone: string
  admin_phone: string
}

export const statusConfig: Record<OrderStatus, { label: string; color: string }> = {
  available: { label: 'Доступен', color: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300' },
  taken: { label: 'Взят', color: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-300' },
  in_transit: { label: 'В пути', color: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300' },
  delivered: { label: 'Доставлен', color: 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-300' },
  cancelled: { label: 'Отменён', color: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300' },
}