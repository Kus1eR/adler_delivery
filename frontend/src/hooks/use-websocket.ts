import { useEffect, useRef, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { wsUrl } from '../lib/axios'

type WsEvent =
  | 'order_created'
  | 'order_taken'
  | 'order_status_changed'
  | 'order_cancelled'
  | 'courier_created'
  | 'courier_status_changed'

const eventMessages: Record<string, string> = {
  order_created: 'Новый заказ создан',
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

  const connect = useCallback(() => {
    const url = wsUrl()
    if (!url.includes('token=')) return

    const ws = new WebSocket(url)
    wsRef.current = ws

    ws.onopen = () => {
      attemptRef.current = 0
    }

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data) as { event: WsEvent; data: Record<string, unknown> }
        const message = eventMessages[msg.event] || msg.event

        // Invalidate relevant queries
        if (msg.event.startsWith('order_')) {
          queryClient.invalidateQueries({ queryKey: ['orders'] })
          queryClient.invalidateQueries({ queryKey: ['stats'] })
        }
        if (msg.event.startsWith('courier_')) {
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
      const delay = Math.min(1000 * 2 ** attemptRef.current, 30000)
      attemptRef.current++
      reconnectTimerRef.current = setTimeout(connect, delay)
    }

    ws.onerror = () => {
      ws.close()
    }
  }, [queryClient])

  useEffect(() => {
    connect()
    return () => {
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