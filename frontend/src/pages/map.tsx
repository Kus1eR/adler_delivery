import { MapProvider } from '../components/map/map-provider'

export default function MapPage() {
  return (
    <div>
      <h2 className="text-xl font-bold mb-4">Карта курьеров и заказов</h2>
      <MapProvider />
    </div>
  )
}
