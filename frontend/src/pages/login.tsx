import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useNavigate } from 'react-router-dom'
import { useMutation } from '@tanstack/react-query'
import { toast } from 'sonner'
import { authApi } from '../api/auth'
import { useAuthStore } from '../stores/auth.store'
import { Button } from '../components/ui/button'
import { Input } from '../components/ui/input'
import { Label } from '../components/ui/label'
import { LogIn } from 'lucide-react'

const loginSchema = z.object({
  username: z.string().min(1, 'Введите логин'),
  password: z.string().min(1, 'Введите пароль'),
})

type LoginForm = z.infer<typeof loginSchema>

export default function LoginPage() {
  const navigate = useNavigate()
  const { setAuth } = useAuthStore()

  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  })

  const loginMutation = useMutation({
    mutationFn: authApi.login,
    onSuccess: (data) => {
      setAuth(data.access_token, data.role, data.user_id)
      toast.success('Вход выполнен')
      navigate('/dashboard')
    },
    onError: () => {
      toast.error('Неверный логин или пароль')
    },
  })

  const onSubmit = (data: LoginForm) => loginMutation.mutate(data)

  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-50 dark:bg-zinc-900 p-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <h1 className="text-2xl font-bold">Dostavka Admin</h1>
          <p className="text-sm text-zinc-500 mt-1">Вход в панель управления</p>
        </div>
        <form
          onSubmit={handleSubmit(onSubmit)}
          className="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm dark:border-zinc-800 dark:bg-zinc-950 space-y-4"
        >
          <div>
            <Label htmlFor="username">Логин</Label>
            <Input id="username" {...register('username')} placeholder="admin" autoFocus />
            {errors.username && <p className="text-sm text-red-500 mt-1">{errors.username.message}</p>}
          </div>
          <div>
            <Label htmlFor="password">Пароль</Label>
            <Input id="password" type="password" {...register('password')} />
            {errors.password && <p className="text-sm text-red-500 mt-1">{errors.password.message}</p>}
          </div>
          <Button
            type="submit"
            className="w-full"
            disabled={isSubmitting || loginMutation.isPending}
          >
            <LogIn className="mr-2 h-4 w-4" />
            {loginMutation.isPending ? 'Вход...' : 'Войти'}
          </Button>
        </form>
      </div>
    </div>
  )
}