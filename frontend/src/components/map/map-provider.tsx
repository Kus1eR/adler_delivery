import { lazy, Suspense, useCallback, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { locationsApi } from '../../api/locations'
import { ordersApi } from '../../api/orders'
import { DEFAULT_MAP_CENTER } from './map-types'

const OsmCourierMap = lazy(() => import('./courier-map'))
const YandexCourierMap = lazy(() => import('./yandex-courier-map'))

function MapLoading() {
  return (
    <div className="flex h-[600px] items-center justify-center rounded-xl bg-zinc-100 dark:bg-zinc-800">
      <p className="text-zinc-500">Загрузка карты...</p>
    </div>
  )
}

export function MapProvider() {
  const configuredProvider = import.meta.env.VITE_MAP_PROVIDER?.toLowerCase()
  const apiKey = import.meta.env.VITE_YANDEX_MAPS_API_KEY?.trim()
  const wantsYandex = configuredProvider === 'yandex'
  const [yandexFailed, setYandexFailed] = useState(false)
  const useYandex = wantsYandex && Boolean(apiKey) && !yandexFailed

  const { data: locations = [], isLoading: locationsLoading } = useQuery({
    queryKey: ['locations'],
    queryFn: locationsApi.get,
    refetchInterval: 15000,
  })
  const { data: ordersPage, isLoading: ordersLoading } = useQuery({
    queryKey: ['orders', 'map'],
    queryFn: async () => {
      const first = await ordersApi.list({ page: 1, perPage: 100 })
      if (first.pages <= 1) return first
      const rest = await Promise.all(
        Array.from({ length: first.pages - 1 }, (_, index) =>
          ordersApi.list({ page: index + 2, perPage: 100 }),
        ),
      )
      return { ...first, items: [first, ...rest].flatMap((page) => page.items) }
    },
    refetchInterval: 30000,
  })
  const orders = useMemo(
    () => (ordersPage?.items ?? []).filter(
      (order) => order.latitude !== 0 && order.longitude !== 0,
    ),
    [ordersPage],
  )
  const center = useMemo<[number, number]>(
    () => locations.length > 0
      ? [locations[0].latitude, locations[0].longitude]
      : DEFAULT_MAP_CENTER,
    [locations],
  )
  const handleYandexError = useCallback(() => setYandexFailed(true), [])

  if (locationsLoading || ordersLoading) return <MapLoading />

  const fallbackReason = wantsYandex && !apiKey
    ? 'Ключ Яндекс Карт не задан — используется OpenStreetMap.'
    : yandexFailed
      ? 'Яндекс Карты недоступны — используется OpenStreetMap.'
      : null

  return (
    <div className="space-y-2">
      {fallbackReason && (
        <p role="status" className="text-sm text-zinc-500 dark:text-zinc-400">
          {fallbackReason}
        </p>
      )}
      <Suspense fallback={<MapLoading />}>
        {useYandex ? (
          <YandexCourierMap
            locations={locations}
            orders={orders}
            center={center}
            onError={handleYandexError}
          />
        ) : (
          <OsmCourierMap locations={locations} orders={orders} center={center} />
        )}
      </Suspense>
    </div>
  )
}
