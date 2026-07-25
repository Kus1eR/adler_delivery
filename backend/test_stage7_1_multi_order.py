import asyncio
import tempfile
from pathlib import Path

import httpx

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import create_access_token
from app.database import get_db
from app.main import app
from app.models import Admin, Base, Courier, Order


async def seed(session_factory: async_sessionmaker) -> None:
    async with session_factory() as db:
        db.add_all(
            [
                Admin(id=1, username="admin", hashed_password="x"),
                Courier(
                    id=1,
                    name="Courier",
                    phone="+70000000001",
                    hashed_password="x",
                ),
                Order(
                    id=1,
                    order_number="MULTI-1",
                    address="First address",
                    price=100,
                    courier_fee=10,
                    status="available",
                    latitude=1,
                    longitude=2,
                ),
                Order(
                    id=2,
                    order_number="MULTI-2",
                    address="Second address",
                    price=200,
                    courier_fee=20,
                    status="available",
                    latitude=3,
                    longitude=4,
                ),
                Order(
                    id=3,
                    order_number="CANCEL-1",
                    address="Cancelled address",
                    price=300,
                    courier_fee=30,
                    status="available",
                    latitude=5,
                    longitude=6,
                ),
            ]
        )
        await db.commit()


async def main() -> None:
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
    )
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    await seed(session_factory)

    async def override_db():
        async with session_factory() as db:
            yield db

    app.dependency_overrides[get_db] = override_db
    headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'courier'})}"
    }
    admin_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'admin'})}"
    }

    try:
        with TestClient(app) as client:
            for order_id in (1, 2):
                response = client.post(
                    f"/api/v1/courier/orders/{order_id}/take",
                    headers=headers,
                )
                assert response.status_code == 200, response.text

            mine = client.get("/api/v1/courier/orders/my", headers=headers)
            assert mine.status_code == 200, mine.text
            assert {order["id"] for order in mine.json()} == {1, 2}, mine.json()

            first = client.patch(
                "/api/v1/courier/orders/1/status",
                headers=headers,
                json={"status": "in_transit"},
            )
            assert first.status_code == 200, first.text

            mine = client.get("/api/v1/courier/orders/my", headers=headers).json()
            statuses = {order["id"]: order["status"] for order in mine}
            assert statuses == {1: "in_transit", 2: "taken"}, statuses

            second = client.patch(
                "/api/v1/courier/orders/2/status",
                headers=headers,
                json={"status": "in_transit"},
            )
            assert second.status_code == 200, second.text

            mine = client.get("/api/v1/courier/orders/my", headers=headers).json()
            statuses = {order["id"]: order["status"] for order in mine}
            assert statuses == {1: "in_transit", 2: "in_transit"}, statuses

            cancelled = client.patch(
                "/api/v1/admin/orders/3/cancel",
                headers=admin_headers,
                params={"reason": "Recipient declined delivery"},
            )
            assert cancelled.status_code == 200, cancelled.text

            orders = client.get(
                "/api/v1/admin/orders",
                headers=admin_headers,
                params={"status": "cancelled"},
            )
            assert orders.status_code == 200, orders.text
            cancelled_order = orders.json()["items"][0]
            assert cancelled_order["id"] == 3, cancelled_order
            assert cancelled_order["cancel_reason"] == "Recipient declined delivery", cancelled_order

            missing_reason = client.patch(
                "/api/v1/admin/orders/2/cancel",
                headers=admin_headers,
            )
            assert missing_reason.status_code == 422, missing_reason.text
    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


async def concurrent_take_regression() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "race.db"
        engine = create_async_engine(f"sqlite+aiosqlite:///{db_path}")
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        await seed(session_factory)

        async def override_db():
            async with session_factory() as db:
                yield db

        app.dependency_overrides[get_db] = override_db
        headers = {
            "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'courier'})}"
        }
        transport = httpx.ASGITransport(app=app)
        try:
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                responses = await asyncio.gather(
                    client.post("/api/v1/courier/orders/1/take", headers=headers),
                    client.post("/api/v1/courier/orders/1/take", headers=headers),
                )
            assert sorted(response.status_code for response in responses) == [200, 409], [
                (response.status_code, response.text) for response in responses
            ]
        finally:
            app.dependency_overrides.clear()
            await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
    asyncio.run(concurrent_take_regression())
    print("stage 7.1 multi-order regression check: OK")
