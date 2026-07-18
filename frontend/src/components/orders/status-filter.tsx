import { Tabs } from '../ui/tabs'

const statusTabs = [
  { key: '', label: 'Все' },
  { key: 'available', label: 'Доступны' },
  { key: 'taken', label: 'Взяты' },
  { key: 'in_transit', label: 'В пути' },
  { key: 'delivered', label: 'Доставлены' },
]

interface StatusFilterProps {
  value: string
  onChange: (value: string) => void
}

export function StatusFilter({ value, onChange }: StatusFilterProps) {
  return (
    <Tabs
      tabs={statusTabs}
      activeKey={value}
      onChange={onChange}
      className="mb-4"
    />
  )
}