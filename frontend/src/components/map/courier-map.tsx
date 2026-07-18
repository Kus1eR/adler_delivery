import { useMemo } from 'react'
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'
import { useQuery } from '@tanstack/react-query'
import { locationsApi } from '../../api/locations'
import L from 'leaflet'

// Fix default marker icon for Leaflet + bundlers
// @ts-expect-error - Leaflet icon issue with bundlers
delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
})

const DEFAULT_CENTER: [number, number] = [55.7558, 37.6173] // Moscow

export function CourierMap() {
  const { data: locations = [], isLoading } = useQuery({
    queryKey: ['locations'],
    queryFn: locationsApi.get,
    refetchInterval: 15000,
  })

  const center = useMemo(() => {
    if (locations.length > 0) {
      return [locations[0].latitude, locations[0].longitude] as [number, number]
    }
    return DEFAULT_CENTER
  }, [locations])

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-[600px] bg-zinc-100 dark:bg-zinc-800 rounded-xl">
        <p className="text-zinc-500">Загрузка карты...</p>
      </div>
    )
  }

  return (
    <div className="h-[600px] rounded-xl overflow-hidden border border-zinc-200 dark:border-zinc-800">
      <MapContainer
        center={center}
        zoom={12}
        className="h-full w-full"
        scrollWheelZoom={true}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        {locations.map((loc) => (
          <Marker key={loc.courier_id} position={[loc.latitude, loc.longitude]}>
            <Popup>
              <div className="text-sm">
                <strong>{loc.courier_name}</strong>
                <br />
                <span className="text-zinc-500">
                  Обновлено: {new Date(loc.updated_at).toLocaleString('ru-RU')}
                </span>
              </div>
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  )
}