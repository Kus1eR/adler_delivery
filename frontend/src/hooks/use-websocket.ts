import { useEffect, useRef, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useAuthStore } from '../stores/auth.store'

type WsEvent =
  | 'order_created'
  | 'order_updated'
  | 'order_taken'
  | 'order_status_changed'
  | 'order_cancelled'
  | 'courier_created'
  | 'courier_status_changed'

const eventMessages: Record<string, string> = {
  order_created: 'Новый заказ создан',
  order_updated: 'Заказ обновлён',
  order_taken: 'Заказ взят курьером',
  order_status_changed: 'Статус заказа изменён',
  order_cancelled: 'Заказ отменён',
  courier_created: 'Новый курьер создан',
  courier_status_changed: 'Статус курьера изменён',
}

export function useWebSocket() {
  const queryClient = useQueryClient()
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const attemptRef = useRef(0)
  const activeRef = useRef(false)

  const connect = useCallback(() => {
    if (!activeRef.current) return
    const token = useAuthStore.getState().token
    if (!token) return

    const base = import.meta.env.VITE_API_BASE_URL || ''
    const wsBase = base.replace(/^http/, 'ws')
    const url = `${wsBase}/ws/admin`

    const ws = new WebSocket(url, [token])
    wsRef.current = ws

    ws.onopen = () => {
      attemptRef.current = 0
    }

    ws.onmessage = (event) => {
      try {
        if (typeof event.data !== 'string') return
        const msg = JSON.parse(event.data) as { event?: unknown; data?: unknown }
        if (typeof msg.event !== 'string' || !(msg.event in eventMessages)) return
        const eventName = msg.event as WsEvent
        const message = eventMessages[eventName]

        // Invalidate relevant queries
        if (eventName.startsWith('order_')) {
          queryClient.invalidateQueries({ queryKey: ['orders'] })
          queryClient.invalidateQueries({ queryKey: ['stats'] })
        }
        if (eventName.startsWith('courier_')) {
          queryClient.invalidateQueries({ queryKey: ['couriers'] })
          queryClient.invalidateQueries({ queryKey: ['stats'] })
        }

        toast.info(message)
      } catch {
        // Ignore non-JSON messages
      }
    }

    ws.onclose = () => {
      wsRef.current = null
      if (!activeRef.current) return
      const delay = Math.min(1000 * 2 ** attemptRef.current, 30000)
      attemptRef.current++
      reconnectTimerRef.current = setTimeout(connect, delay)
    }

    ws.onerror = () => {
      ws.close()
    }
  }, [queryClient])

  useEffect(() => {
    activeRef.current = true
    connect()
    return () => {
      activeRef.current = false
      if (wsRef.current) {
        wsRef.current.close()
      }
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current)
      }
    }
  }, [connect])

  return wsRef
}
