import asyncio

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import get_current_admin
from app.database import get_db
from app.main import app
from app.models import Admin, Base, Order


async def seed(session_factory: async_sessionmaker) -> None:
    async with session_factory() as db:
        db.add_all(
            [
                Order(
                    order_number="order-001",
                    address="Lenina 1",
                    price=100,
                    courier_fee=10,
                    status="available",
                    latitude=1,
                    longitude=1,
                ),
                Order(
                    order_number="ABC-002",
                    address="ORDER street",
                    price=200,
                    courier_fee=20,
                    status="taken",
                    latitude=2,
                    longitude=2,
                ),
                Order(
                    order_number="ORDER-DELETED",
                    address="Hidden",
                    price=300,
                    courier_fee=30,
                    status="available",
                    latitude=3,
                    longitude=3,
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

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_admin] = lambda: Admin(
        id=1,
        username="test",
        hashed_password="x",
    )
    try:
        with TestClient(app) as client:
            response = client.get(
                "/api/admin/orders",
                params={"page": 1, "per_page": 1, "search": "order"},
            )
            assert response.status_code == 200, response.text
            body = response.json()
            assert body["total"] == 2, body
            assert body["page"] == 1, body
            assert body["per_page"] == 1, body
            assert body["pages"] == 2, body
            assert len(body["items"]) == 1, body

            filtered = client.get(
                "/api/admin/orders",
                params={"status": "taken", "search": "order"},
            ).json()
            assert filtered["total"] == 1, filtered
            assert filtered["items"][0]["order_number"] == "ABC-002", filtered
            assert client.get("/api/admin/orders", params={"page": 0}).status_code == 422
            assert client.get("/api/admin/orders", params={"per_page": 101}).status_code == 422
    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
    print("admin orders HTTP pagination/search check: OK")
