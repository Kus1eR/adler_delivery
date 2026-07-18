import json
from typing import Any

from fastapi import WebSocket


class WebSocketManager:
    def __init__(self):
        self.admin_connections: list[WebSocket] = []
        self.courier_connections: dict[int, list[WebSocket]] = {}

    async def connect_admin(self, ws: WebSocket):
        await ws.accept()
        self.admin_connections.append(ws)

    def disconnect_admin(self, ws: WebSocket):
        if ws in self.admin_connections:
            self.admin_connections.remove(ws)

    async def connect_courier(self, courier_id: int, ws: WebSocket):
        await ws.accept()
        self.courier_connections.setdefault(courier_id, []).append(ws)

    def disconnect_courier(self, courier_id: int, ws: WebSocket):
        conns = self.courier_connections.get(courier_id, [])
        if ws in conns:
            conns.remove(ws)

    async def broadcast_to_admins(self, event: str, data: dict[str, Any]):
        msg = json.dumps({"event": event, "data": data})
        for ws in self.admin_connections.copy():
            try:
                await ws.send_text(msg)
            except Exception:
                self.disconnect_admin(ws)

    async def send_to_courier(self, courier_id: int, event: str, data: dict[str, Any]):
        msg = json.dumps({"event": event, "data": data})
        for ws in self.courier_connections.get(courier_id, []).copy():
            try:
                await ws.send_text(msg)
            except Exception:
                self.disconnect_courier(courier_id, ws)

    async def broadcast_to_all_couriers(self, event: str, data: dict[str, Any]):
        msg = json.dumps({"event": event, "data": data})
        for courier_id in list(self.courier_connections.keys()):
            for ws in self.courier_connections[courier_id].copy():
                try:
                    await ws.send_text(msg)
                except Exception:
                    self.disconnect_courier(courier_id, ws)


ws_manager = WebSocketManager()
