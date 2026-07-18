export type CourierStatus = 'active' | 'blocked'

export interface Courier {
  id: number
  name: string
  phone: string
  status: CourierStatus
  created_at: string
}

export interface CourierCreate {
  name: string
  phone: string
}

export const courierStatusConfig: Record<CourierStatus, { label: string; color: string }> = {
  active: { label: 'Активен', color: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300' },
  blocked: { label: 'Заблокирован', color: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300' },
}