import asyncio
import logging
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from jose import JWTError, jwt
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from sqlalchemy import select

from app.config import settings
from app.database import async_session, engine
from app.models import Admin, Base, Courier
from app.limiter import limiter
from app.routers import admin, courier
from app.ws_manager import ws_manager

logging.basicConfig(level=logging.INFO)

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(title="Dostavka API", lifespan=lifespan)

app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.include_router(admin.router, prefix="/api/admin", deprecated=True)
app.include_router(admin.router, prefix="/api/v1/admin")
app.include_router(courier.router, prefix="/api/courier", deprecated=True)
app.include_router(courier.router, prefix="/api/v1/courier")


@app.get("/")
async def root():
    return {"message": "Dostavka API is running"}


@app.websocket("/ws/admin")
async def admin_websocket(ws: WebSocket):
    token = ws.headers.get("sec-websocket-protocol")
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("role") != "admin":
            await ws.close(code=4001)
            return
        admin_id = int(payload.get("sub"))
    except (JWTError, TypeError, ValueError):
        await ws.close(code=4001)
        return
    async with async_session() as db:
        admin = await db.scalar(
            select(Admin).where(Admin.id == admin_id, Admin.is_active.is_(True))
        )
    if admin is None:
        await ws.close(code=4001)
        return
    await ws_manager.connect_admin(ws, token)
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect_admin(ws)


@app.websocket("/ws/courier/{courier_id}")
async def courier_websocket(ws: WebSocket, courier_id: int):
    token = ws.headers.get("sec-websocket-protocol")
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("role") != "courier" or int(payload.get("sub")) != courier_id:
            await ws.close(code=4001)
            return
    except (JWTError, TypeError, ValueError):
        await ws.close(code=4001)
        return
    async with async_session() as db:
        courier = await db.scalar(
            select(Courier).where(
                Courier.id == courier_id, Courier.status != "blocked"
            )
        )
    if courier is None:
        await ws.close(code=4001)
        return
    await ws_manager.connect_courier(courier_id, ws, token)
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect_courier(courier_id, ws)
