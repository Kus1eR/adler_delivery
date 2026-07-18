import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import { ProtectedRoute } from './components/auth/protected-route'
import { DashboardLayout } from './components/layout/dashboard-layout'
import LoginPage from './pages/login'
import OrdersPage from './pages/orders'
import CouriersPage from './pages/couriers'
import StatsPage from './pages/stats'
import MapPage from './pages/map'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 10000,
    },
  },
})

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<DashboardLayout />}>
              <Route path="/dashboard" element={<OrdersPage />} />
              <Route path="/dashboard/couriers" element={<CouriersPage />} />
              <Route path="/dashboard/stats" element={<StatsPage />} />
              <Route path="/dashboard/map" element={<MapPage />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
      </BrowserRouter>
      <Toaster position="top-right" richColors />
    </QueryClientProvider>
  )
}