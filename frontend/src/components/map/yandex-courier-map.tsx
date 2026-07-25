import { useEffect, useRef } from 'react'
import type { MapRendererProps } from './map-types'

interface YandexMapInstance {
  geoObjects: { add(object: unknown): void }
  destroy(): void
}

interface YandexMapsApi {
  ready(callback: () => void): void
  Map: new (
    element: HTMLElement,
    state: { center: [number, number]; zoom: number; controls: string[] },
  ) => YandexMapInstance
  Placemark: new (
    coordinates: [number, number],
    properties: { balloonContent: string; hintContent: string },
    options?: { preset: string },
  ) => unknown
}

declare global {
  interface Window {
    ymaps?: YandexMapsApi
  }
}

const SCRIPT_ID = 'yandex-maps-js-api'
let apiPromise: Promise<YandexMapsApi> | undefined

function loadYandexMaps(apiKey: string): Promise<YandexMapsApi> {
  if (window.ymaps) return Promise.resolve(window.ymaps)
  if (apiPromise) return apiPromise

  const promise = new Promise<YandexMapsApi>((resolve, reject) => {
    const loadTimeout = window.setTimeout(
      () => reject(new Error('Yandex Maps script loading timed out')),
      10_000,
    )
    const ready = () => {
      window.clearTimeout(loadTimeout)
      if (!window.ymaps) {
        reject(new Error('Yandex Maps API unavailable'))
        return
      }
      const timeout = window.setTimeout(
        () => reject(new Error('Yandex Maps API initialization timed out')),
        10_000,
      )
      window.ymaps.ready(() => {
        window.clearTimeout(timeout)
        resolve(window.ymaps!)
      })
    }

    const existing = document.getElementById(SCRIPT_ID) as HTMLScriptElement | null
    if (existing) {
      existing.addEventListener('load', ready, { once: true })
      existing.addEventListener('error', () => {
        window.clearTimeout(loadTimeout)
        reject(new Error('Yandex Maps script failed'))
      }, {
        once: true,
      })
      return
    }

    const script = document.createElement('script')
    script.id = SCRIPT_ID
    script.async = true
    script.src = `https://api-maps.yandex.ru/2.1/?apikey=${encodeURIComponent(apiKey)}&lang=ru_RU`
    script.addEventListener('load', ready, { once: true })
    script.addEventListener('error', () => {
      window.clearTimeout(loadTimeout)
      reject(new Error('Yandex Maps script failed'))
    }, {
      once: true,
    })
    document.head.appendChild(script)
  }).catch((error: unknown): never => {
    apiPromise = undefined
    document.getElementById(SCRIPT_ID)?.remove()
    throw error
  })

  apiPromise = promise
  return promise
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    "'": '&#39;',
    '"': '&quot;',
  })[character]!)
}

export default function YandexCourierMap({
  locations,
  orders,
  center,
  onError,
}: MapRendererProps) {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let disposed = false
    let map: YandexMapInstance | undefined
    const apiKey = import.meta.env.VITE_YANDEX_MAPS_API_KEY?.trim()

    if (!apiKey || !containerRef.current) {
      onError?.()
      return
    }

    loadYandexMaps(apiKey)
      .then((ymaps) => {
        if (disposed || !containerRef.current) return
        map = new ymaps.Map(containerRef.current, {
          center,
          zoom: 12,
          controls: ['zoomControl', 'fullscreenControl'],
        })

        locations.forEach((location) => {
          map?.geoObjects.add(new ymaps.Placemark(
            [location.latitude, location.longitude],
            {
              hintContent: escapeHtml(location.courier_name),
              balloonContent: `<strong>${escapeHtml(location.courier_name)}</strong><br>Обновлено: ${escapeHtml(new Date(location.updated_at).toLocaleString('ru-RU'))}`,
            },
            { preset: 'islands#redIcon' },
          ))
        })

        orders.forEach((order) => {
          map?.geoObjects.add(new ymaps.Placemark(
            [order.latitude, order.longitude],
            {
              hintContent: `Заказ ${escapeHtml(order.order_number)}`,
              balloonContent: `<strong>Заказ ${escapeHtml(order.order_number)}</strong><br>${escapeHtml(order.address)}<br>Статус: ${escapeHtml(order.status)}`,
            },
            { preset: 'islands#blueIcon' },
          ))
        })
      })
      .catch(() => {
        if (!disposed) onError?.()
      })

    return () => {
      disposed = true
      map?.destroy()
    }
  }, [center, locations, onError, orders])

  return (
    <div className="h-[600px] overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
      <div ref={containerRef} className="h-full w-full" aria-label="Карта курьеров и заказов" />
    </div>
  )
}
