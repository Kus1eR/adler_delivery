import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { Package, Users, BarChart3, Map, LogOut, Menu, Moon, Shield, Sun, X } from 'lucide-react'
import { Button } from '../ui/button'
import { useAuthStore } from '../../stores/auth.store'
import { useWebSocket } from '../../hooks/use-websocket'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { adminsApi } from '../../api/admins'
import { applyTheme, initialTheme, type Theme } from '../../lib/theme'

const navItems = [
  { to: '/dashboard', icon: Package, label: 'Заказы' },
  { to: '/dashboard/couriers', icon: Users, label: 'Курьеры' },
  { to: '/dashboard/stats', icon: BarChart3, label: 'Статистика' },
  { to: '/dashboard/map', icon: Map, label: 'Карта' },
]

export function DashboardLayout() {
  const { clearAuth } = useAuthStore()
  const navigate = useNavigate()
  const [mobileOpen, setMobileOpen] = useState(false)
  const [theme, setTheme] = useState<Theme>(initialTheme)
  const { data: currentAdmin } = useQuery({
    queryKey: ['current-admin'],
    queryFn: adminsApi.me,
  })
  useWebSocket()

  const visibleNavItems = currentAdmin?.is_superadmin
    ? [...navItems, { to: '/dashboard/admins', icon: Shield, label: 'Администраторы' }]
    : navItems

  const toggleTheme = () => {
    const nextTheme = theme === 'dark' ? 'light' : 'dark'
    setTheme(nextTheme)
    applyTheme(nextTheme)
  }

  const handleLogout = () => {
    clearAuth()
    navigate('/login')
  }

  const NavLinks = () => (
    <nav className="space-y-1">
      {visibleNavItems.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.to === '/dashboard'}
          onClick={() => setMobileOpen(false)}
          className={({ isActive }) =>
            `flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
              isActive
                ? 'bg-zinc-900 text-white dark:bg-zinc-50 dark:text-zinc-900'
                : 'text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-50'
            }`
          }
        >
          <item.icon className="h-4 w-4" />
          {item.label}
        </NavLink>
      ))}
    </nav>
  )

  return (
    <div className="flex h-screen bg-zinc-50 dark:bg-zinc-900">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex w-64 flex-col border-r border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
        <div className="flex h-14 items-center border-b border-zinc-200 px-6 dark:border-zinc-800">
          <h1 className="text-lg font-bold">Dostavka Admin</h1>
        </div>
        <div className="flex-1 overflow-auto p-4">
          <NavLinks />
        </div>
        <div className="border-t border-zinc-200 p-4 dark:border-zinc-800">
          <Button
            variant="outline"
            className="w-full justify-start gap-2"
            onClick={handleLogout}
          >
            <LogOut className="h-4 w-4" />
            Выйти
          </Button>
        </div>
      </aside>

      {/* Mobile header */}
      <div className="flex flex-1 flex-col overflow-hidden">
        <header className="flex h-14 items-center justify-between border-b border-zinc-200 bg-white px-4 dark:border-zinc-800 dark:bg-zinc-950 md:hidden">
          <h1 className="text-lg font-bold">Dostavka Admin</h1>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="icon" onClick={toggleTheme} aria-label="Переключить тему">
              {theme === 'dark' ? <Sun className="h-5 w-5" /> : <Moon className="h-5 w-5" />}
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setMobileOpen(!mobileOpen)}
              aria-label={mobileOpen ? 'Закрыть меню' : 'Открыть меню'}
              aria-expanded={mobileOpen}
            >
              {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </Button>
          </div>
        </header>

        {/* Desktop header */}
        <header className="hidden md:flex h-14 items-center justify-end border-b border-zinc-200 bg-white px-6 dark:border-zinc-800 dark:bg-zinc-950">
          <Button variant="ghost" size="icon" className="mr-2" onClick={toggleTheme} aria-label="Переключить тему">
            {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
          </Button>
          <Button variant="outline" size="sm" className="gap-2" onClick={handleLogout}>
            <LogOut className="h-4 w-4" />
            Выйти
          </Button>
        </header>

        {/* Mobile nav overlay */}
        {mobileOpen && (
          <div className="md:hidden fixed inset-0 z-40">
            <div
              className="absolute inset-0 bg-black/50"
              onClick={() => setMobileOpen(false)}
            />
            <div className="absolute left-0 top-0 bottom-0 w-64 bg-white dark:bg-zinc-950 p-4 pt-16 z-50">
              <NavLinks />
              <div className="mt-4">
                <Button
                  variant="outline"
                  className="w-full justify-start gap-2"
                  onClick={handleLogout}
                >
                  <LogOut className="h-4 w-4" />
                  Выйти
                </Button>
              </div>
            </div>
          </div>
        )}

        {/* Main content */}
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Outlet />
        </main>

        {/* Mobile bottom nav */}
        <nav className="md:hidden flex items-center justify-around border-t border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950 py-2">
          {visibleNavItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/dashboard'}
              className={({ isActive }) =>
                `flex flex-col items-center gap-1 text-xs font-medium ${
                  isActive
                    ? 'text-zinc-900 dark:text-zinc-50'
                    : 'text-zinc-400'
                }`
              }
            >
              <item.icon className="h-5 w-5" />
              {item.label}
            </NavLink>
          ))}
        </nav>
      </div>
    </div>
  )
}
