import asyncio
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from jose import JWTError, jwt

from app.config import settings
from app.database import engine
from app.models import Base
from app.routers import admin, courier
from app.ws_manager import ws_manager

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(title="Dostavka API", lifespan=lifespan)

app.include_router(admin.router)
app.include_router(courier.router)


@app.get("/")
async def root():
    return {"message": "Dostavka API is running"}


@app.websocket("/ws/admin")
async def admin_websocket(ws: WebSocket, token: str = Query(...)):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("role") != "admin":
            await ws.close(code=4001)
            return
    except JWTError:
        await ws.close(code=4001)
        return
    await ws_manager.connect_admin(ws)
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect_admin(ws)


@app.websocket("/ws/courier/{courier_id}")
async def courier_websocket(ws: WebSocket, courier_id: int, token: str = Query(...)):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("role") != "courier" or int(payload.get("sub")) != courier_id:
            await ws.close(code=4001)
            return
    except JWTError:
        await ws.close(code=4001)
        return
    await ws_manager.connect_courier(courier_id, ws)
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect_courier(courier_id, ws)
