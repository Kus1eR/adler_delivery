import { courierStatusConfig } from '../../types'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../ui/table'
import { Switch } from '../ui/switch'
import type { Courier } from '../../types'

interface CouriersTableProps {
  couriers: Courier[]
  onToggleBlock: (courier: Courier) => void
}

export function CouriersTable({ couriers, onToggleBlock }: CouriersTableProps) {
  if (couriers.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-zinc-500">
        <p className="text-lg">Нет курьеров</p>
        <p className="text-sm">Добавьте первого курьера</p>
      </div>
    )
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Имя</TableHead>
          <TableHead>Телефон</TableHead>
          <TableHead>Статус</TableHead>
          <TableHead className="text-right">Действие</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {couriers.map((courier) => {
          const s = courierStatusConfig[courier.status]
          return (
            <TableRow key={courier.id}>
              <TableCell className="font-medium">{courier.name}</TableCell>
              <TableCell>{courier.phone}</TableCell>
              <TableCell>
                <span className={`inline-flex items-center rounded-md px-2.5 py-0.5 text-xs font-semibold ${s.color}`}>
                  {s.label}
                </span>
              </TableCell>
              <TableCell className="text-right">
                <div className="flex items-center justify-end gap-2">
                  <span className="text-xs text-zinc-500">
                    {courier.status === 'blocked' ? 'Разблок' : 'Заблок'}
                  </span>
                  <Switch
                    checked={courier.status === 'blocked'}
                    onCheckedChange={() => onToggleBlock(courier)}
                  />
                </div>
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  )
}