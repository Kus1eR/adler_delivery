import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AxiosError } from 'axios'
import { toast } from 'sonner'
import { adminsApi } from '../api/admins'
import { Button } from '../components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { Input } from '../components/ui/input'
import { Label } from '../components/ui/label'

function errorDetail(error: unknown, fallback: string): string {
  if (error instanceof AxiosError) {
    const data = error.response?.data as { detail?: string } | undefined
    return data?.detail ?? fallback
  }
  return fallback
}

export default function AdminsPage() {
  const queryClient = useQueryClient()
  const [username, setUsername] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [password, setPassword] = useState('')
  const { data: admins = [], isLoading } = useQuery({
    queryKey: ['admins'],
    queryFn: adminsApi.list,
  })

  const createMutation = useMutation({
    mutationFn: adminsApi.create,
    onSuccess: () => {
      toast.success('Администратор создан')
      setUsername('')
      setDisplayName('')
      setPassword('')
      queryClient.invalidateQueries({ queryKey: ['admins'] })
    },
    onError: (error) => toast.error(errorDetail(error, 'Ошибка создания администратора')),
  })

  const statusMutation = useMutation({
    mutationFn: ({ id, isActive }: { id: number; isActive: boolean }) =>
      adminsApi.setActive(id, isActive),
    onSuccess: (admin) => {
      toast.success(admin.is_active ? 'Администратор активирован' : 'Администратор отключён')
      queryClient.invalidateQueries({ queryKey: ['admins'] })
    },
    onError: (error) => toast.error(errorDetail(error, 'Ошибка изменения статуса')),
  })

  const createAdmin = (event: React.FormEvent) => {
    event.preventDefault()
    if (password.length < 8) {
      toast.error('Пароль должен содержать минимум 8 символов')
      return
    }
    createMutation.mutate({
      username: username.trim(),
      password,
      display_name: displayName.trim() || undefined,
    })
  }

  return (
    <div className="space-y-6">
      <h2 className="text-xl font-bold">Администраторы</h2>

      <Card>
        <CardHeader><CardTitle>Новый администратор</CardTitle></CardHeader>
        <CardContent>
          <form onSubmit={createAdmin} className="grid gap-4 md:grid-cols-4 md:items-end">
            <div className="space-y-2">
              <Label htmlFor="admin-username">Логин</Label>
              <Input id="admin-username" value={username} onChange={(event) => setUsername(event.target.value)} required maxLength={100} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="admin-name">Отображаемое имя</Label>
              <Input id="admin-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} maxLength={200} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="admin-password">Пароль</Label>
              <Input id="admin-password" type="password" autoComplete="new-password" minLength={8} value={password} onChange={(event) => setPassword(event.target.value)} required />
            </div>
            <Button type="submit" disabled={createMutation.isPending}>
              {createMutation.isPending ? 'Создание...' : 'Создать'}
            </Button>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="pt-6">
          {isLoading ? <p className="text-sm text-muted-foreground">Загрузка...</p> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead><tr className="border-b text-left"><th className="p-3">Имя</th><th className="p-3">Логин</th><th className="p-3">Роль</th><th className="p-3">Статус</th><th className="p-3 text-right">Действие</th></tr></thead>
                <tbody>
                  {admins.map((admin) => (
                    <tr key={admin.id} className="border-b last:border-0">
                      <td className="p-3">{admin.display_name || '—'}</td>
                      <td className="p-3 font-medium">{admin.username}</td>
                      <td className="p-3">{admin.is_superadmin ? 'Суперадминистратор' : 'Администратор'}</td>
                      <td className="p-3">{admin.is_active ? 'Активен' : 'Отключён'}</td>
                      <td className="p-3 text-right">
                        <Button
                          variant="outline"
                          size="sm"
                          disabled={statusMutation.isPending}
                          onClick={() => {
                            const action = admin.is_active ? 'отключить' : 'активировать'
                            if (window.confirm(`Подтвердите: ${action} администратора ${admin.username}?`)) {
                              statusMutation.mutate({ id: admin.id, isActive: !admin.is_active })
                            }
                          }}
                        >
                          {admin.is_active ? 'Отключить' : 'Активировать'}
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
