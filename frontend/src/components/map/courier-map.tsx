import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { MapRendererProps } from './map-types'

// Fix default marker icon for Leaflet + bundlers
// @ts-expect-error - Leaflet icon issue with bundlers
delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
})

const orderIcon = L.divIcon({
  className: '',
  html: '<div style="width:28px;height:28px;border-radius:8px;background:#2563eb;color:white;display:grid;place-items:center;font-weight:700;border:2px solid white;box-shadow:0 2px 8px #0005">З</div>',
  iconSize: [28, 28],
  iconAnchor: [14, 14],
})

export default function CourierMap({ locations, orders, center }: MapRendererProps) {
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
        {orders.map((order) => (
          <Marker
            key={`order-${order.id}`}
            position={[order.latitude, order.longitude]}
            icon={orderIcon}
          >
            <Popup>
              <div className="text-sm">
                <strong>Заказ {order.order_number}</strong>
                <br />
                <span>{order.address}</span>
                <br />
                <span className="text-zinc-500">Статус: {order.status}</span>
              </div>
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  )
}
