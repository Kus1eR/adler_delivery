import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { AuthState } from '../types'

interface AuthStore extends AuthState {
  setAuth: (token: string, role: string, userId: number) => void
  clearAuth: () => void
}

export const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      token: null,
      role: null,
      userId: null,
      isAuthenticated: false,
      setAuth: (token, role, userId) =>
        set({ token, role, userId, isAuthenticated: true }),
      clearAuth: () =>
        set({ token: null, role: null, userId: null, isAuthenticated: false }),
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        token: state.token,
        role: state.role,
        userId: state.userId,
        isAuthenticated: state.isAuthenticated,
      }),
    },
  ),
)