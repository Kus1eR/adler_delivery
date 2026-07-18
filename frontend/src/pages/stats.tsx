import { useQuery } from '@tanstack/react-query'
import { ordersApi } from '../api/orders'
import { StatCards } from '../components/stats/stat-cards'
import { RotateCw } from 'lucide-react'
import { Button } from '../components/ui/button'

export default function StatsPage() {
  const { data: stats, isLoading, refetch } = useQuery({
    queryKey: ['stats'],
    queryFn: ordersApi.stats,
    refetchInterval: 30000,
  })

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12 text-zinc-500">
        Загрузка...
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Статистика</h2>
        <Button variant="outline" size="icon" onClick={() => refetch()}>
          <RotateCw className="h-4 w-4" />
        </Button>
      </div>
      {stats && <StatCards stats={stats} />}
    </div>
  )
}