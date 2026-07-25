import asyncio

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import create_access_token
from app.database import async_session, get_db
from app.main import app
from app.models import Admin, Base, Courier


async def seed(session_factory: async_sessionmaker) -> None:
    async with session_factory() as db:
        db.add_all([
            Admin(id=1, username="active", hashed_password="x", is_active=True),
            Admin(id=2, username="inactive", hashed_password="x", is_active=False),
            Courier(id=1, name="Active", phone="+70000000001", hashed_password="x"),
            Courier(id=2, name="Blocked", phone="+70000000002", hashed_password="x", status="blocked"),
        ])
        await db.commit()


def rejected(client: TestClient, path: str, token: str) -> None:
    try:
        with client.websocket_connect(path, subprotocols=[token]):
            raise AssertionError("WebSocket unexpectedly accepted")
    except WebSocketDisconnect as exc:
        assert exc.code == 4001, exc.code


def main() -> None:
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def setup() -> None:
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        await seed(session_factory)

    async def override_db():
        async with session_factory() as db:
            yield db

    asyncio.run(setup())
    app.dependency_overrides[get_db] = override_db
    original_session = async_session
    try:
        import app.main as main_module
        main_module.async_session = session_factory
        with TestClient(app) as client:
            admin_token = create_access_token({"sub": 1, "role": "admin"})
            with client.websocket_connect("/ws/admin", subprotocols=[admin_token]) as websocket:
                assert websocket.accepted_subprotocol == admin_token

            courier_token = create_access_token({"sub": 1, "role": "courier"})
            with client.websocket_connect("/ws/courier/1", subprotocols=[courier_token]) as websocket:
                assert websocket.accepted_subprotocol == courier_token

            rejected(client, "/ws/admin", create_access_token({"sub": 2, "role": "admin"}))
            rejected(client, "/ws/admin", create_access_token({"sub": 999, "role": "admin"}))
            rejected(client, "/ws/courier/2", create_access_token({"sub": 2, "role": "courier"}))
            rejected(client, "/ws/courier/1", create_access_token({"sub": 1, "role": "admin"}))
    finally:
        app.dependency_overrides.clear()
        main_module.async_session = original_session
        asyncio.run(engine.dispose())


if __name__ == "__main__":
    main()
    print("WebSocket subprotocol auth and role checks: OK")
