import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import type { Stats } from '../../types'
import { Package, CheckCircle, Truck, MapPin, Users, UserCheck } from 'lucide-react'

interface StatCardsProps {
  stats: Stats
}

const items = [
  { key: 'total_orders' as const, label: 'Всего заказов', icon: Package },
  { key: 'available' as const, label: 'Доступно', icon: MapPin },
  { key: 'in_transit' as const, label: 'В пути', icon: Truck },
  { key: 'delivered' as const, label: 'Доставлено', icon: CheckCircle },
  { key: 'total_couriers' as const, label: 'Всего курьеров', icon: Users },
  { key: 'active_couriers' as const, label: 'Активных курьеров', icon: UserCheck },
]

export function StatCards({ stats }: StatCardsProps) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
      {items.map(({ key, label, icon: Icon }) => (
        <Card key={key}>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500 dark:text-zinc-400">
              {label}
            </CardTitle>
            <Icon className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats[key]}</div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}