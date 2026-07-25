import { lazy, Suspense } from 'react'
import { BrowserRouter, Routes, Route, Navigate, Outlet } from 'react-router-dom'
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import { ProtectedRoute } from './components/auth/protected-route'
import { DashboardLayout } from './components/layout/dashboard-layout'
import { adminsApi } from './api/admins'

const LoginPage = lazy(() => import('./pages/login'))
const OrdersPage = lazy(() => import('./pages/orders'))
const CouriersPage = lazy(() => import('./pages/couriers'))
const StatsPage = lazy(() => import('./pages/stats'))
const MapPage = lazy(() => import('./pages/map'))
const AdminsPage = lazy(() => import('./pages/admins'))

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 10000,
    },
  },
})

function SuperadminRoute() {
  const { data: admin, isLoading } = useQuery({
    queryKey: ['current-admin'],
    queryFn: adminsApi.me,
  })
  if (isLoading) return null
  return admin?.is_superadmin ? <Outlet /> : <Navigate to="/dashboard" replace />
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Suspense
          fallback={
            <div role="status" aria-live="polite" className="grid min-h-screen place-items-center text-sm text-zinc-600">
              Загрузка…
            </div>
          }
        >
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route element={<ProtectedRoute />}>
              <Route element={<DashboardLayout />}>
                <Route path="/dashboard" element={<OrdersPage />} />
                <Route path="/dashboard/couriers" element={<CouriersPage />} />
                <Route path="/dashboard/stats" element={<StatsPage />} />
                <Route path="/dashboard/map" element={<MapPage />} />
                <Route element={<SuperadminRoute />}>
                  <Route path="/dashboard/admins" element={<AdminsPage />} />
                </Route>
              </Route>
            </Route>
            <Route path="*" element={<Navigate to="/dashboard" replace />} />
          </Routes>
        </Suspense>
      </BrowserRouter>
      <Toaster position="top-right" richColors />
    </QueryClientProvider>
  )
}
