import asyncio

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import create_access_token
from app.database import get_db
from app.main import app
from app.models import Admin, Base, Courier, Order, OrderHistory
from app.ws_manager import ws_manager


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
                    order_number="ORDER-1",
                    address="Old address",
                    price=100,
                    courier_fee=10,
                    status="taken",
                    courier_id=1,
                    latitude=1,
                    longitude=2,
                ),
                Order(
                    id=2,
                    order_number="ORDER-2",
                    address="Other address",
                    price=200,
                    courier_fee=20,
                    status="available",
                    latitude=3,
                    longitude=4,
                ),
                Order(
                    id=3,
                    order_number="ORDER-DELETED",
                    address="Deleted address",
                    price=300,
                    courier_fee=30,
                    status="cancelled",
                    latitude=5,
                    longitude=6,
                    is_deleted=True,
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

    admin_events: list[tuple[str, dict]] = []
    courier_events: list[tuple[int, str, dict]] = []

    async def capture_admin(event: str, data: dict) -> None:
        admin_events.append((event, data))

    async def capture_courier(courier_id: int, event: str, data: dict) -> None:
        courier_events.append((courier_id, event, data))

    original_admin_broadcast = ws_manager.broadcast_to_admins
    original_courier_send = ws_manager.send_to_courier
    ws_manager.broadcast_to_admins = capture_admin
    ws_manager.send_to_courier = capture_courier
    app.dependency_overrides[get_db] = override_db

    admin_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'admin'})}"
    }
    courier_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'courier'})}"
    }

    try:
        with TestClient(app) as client:
            response = client.patch(
                "/api/admin/orders/1",
                headers=admin_headers,
                json={
                    "order_number": "ORDER-1A",
                    "address": "New address",
                    "price": 150.5,
                    "courier_fee": 15,
                    "description": "Updated",
                    "recipient_phone": "+70000000002",
                    "admin_phone": "+70000000003",
                    "latitude": 10.5,
                    "longitude": 20.5,
                },
            )
            assert response.status_code == 200, response.text
            body = response.json()
            assert body["order_number"] == "ORDER-1A", body
            assert body["status"] == "taken", body
            assert body["courier_id"] == 1, body
            assert admin_events == [
                ("order_updated", {"id": 1, "order_number": "ORDER-1A"})
            ], admin_events
            assert courier_events == [
                (1, "order_updated", {"id": 1, "order_number": "ORDER-1A"})
            ], courier_events

            duplicate = client.patch(
                "/api/admin/orders/1",
                headers=admin_headers,
                json={"order_number": "ORDER-2"},
            )
            assert duplicate.status_code == 409, duplicate.text
            assert duplicate.json()["detail"] == "Order number already exists"

            empty = client.patch(
                "/api/admin/orders/1", headers=admin_headers, json={}
            )
            assert empty.status_code == 422, empty.text

            deleted = client.patch(
                "/api/admin/orders/3",
                headers=admin_headers,
                json={"address": "Visible"},
            )
            assert deleted.status_code == 404, deleted.text

            forbidden_field = client.patch(
                "/api/admin/orders/1",
                headers=admin_headers,
                json={"status": "delivered"},
            )
            assert forbidden_field.status_code == 422, forbidden_field.text

            invalid_coordinates = client.patch(
                "/api/admin/orders/1",
                headers=admin_headers,
                json={"latitude": 91, "longitude": 181},
            )
            assert invalid_coordinates.status_code == 422, invalid_coordinates.text

            unauthenticated = client.patch(
                "/api/admin/orders/1", json={"address": "Forbidden"}
            )
            assert unauthenticated.status_code in (401, 403), unauthenticated.text

            non_admin = client.patch(
                "/api/admin/orders/1",
                headers=courier_headers,
                json={"address": "Forbidden"},
            )
            assert non_admin.status_code == 403, non_admin.text

        async with session_factory() as db:
            order = await db.scalar(select(Order).where(Order.id == 1))
            assert order is not None
            assert order.address == "New address"
            assert order.status == "taken"
            assert order.courier_id == 1
            history_count = await db.scalar(
                select(func.count()).select_from(OrderHistory)
            )
            assert history_count == 0
    finally:
        app.dependency_overrides.clear()
        ws_manager.broadcast_to_admins = original_admin_broadcast
        ws_manager.send_to_courier = original_courier_send
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
    print("stage 4 admin order update checks: OK")
