import type { CourierLocation, Order } from '../../types'

export const DEFAULT_MAP_CENTER: [number, number] = [55.7558, 37.6173]

export interface MapRendererProps {
  locations: CourierLocation[]
  orders: Order[]
  center: [number, number]
  onError?: () => void
}
