import asyncio

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import hash_password
from app.database import get_db
from app.main import app
from app.models import Admin, Base


async def main() -> None:
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
    )
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    async with session_factory() as db:
        db.add(
            Admin(
                username="admin",
                hashed_password=hash_password("admin123"),
            )
        )
        await db.commit()

    async def override_db():
        async with session_factory() as db:
            yield db

    app.dependency_overrides[get_db] = override_db
    try:
        with TestClient(app) as client:
            admin_login = client.post(
                "/api/admin/login",
                json={"username": "admin", "password": "admin123"},
            )
            assert admin_login.status_code == 200, admin_login.text
            admin_v1_login = client.post(
                "/api/v1/admin/login",
                json={"username": "admin", "password": "admin123"},
            )
            assert admin_v1_login.status_code == 200, admin_v1_login.text
            assert admin_v1_login.json()["role"] == admin_login.json()["role"]
            headers = {
                "Authorization": f"Bearer {admin_login.json()['access_token']}"
            }
            legacy_orders = client.get("/api/admin/orders", headers=headers)
            v1_orders = client.get("/api/v1/admin/orders", headers=headers)
            assert legacy_orders.status_code == v1_orders.status_code == 200
            assert legacy_orders.json() == v1_orders.json()

            assert client.post(
                "/api/admin/couriers",
                headers=headers,
                json={
                    "name": "Test Courier",
                    "phone": "8 (900) 123-45-67",
                    "password": "short",
                },
            ).status_code == 422

            created = client.post(
                "/api/admin/couriers",
                headers=headers,
                json={
                    "name": "Test Courier",
                    "phone": "8 (900) 123-45-67",
                    "password": "courier123",
                },
            )
            assert created.status_code == 200, created.text
            assert created.json()["phone"] == "+79001234567"
            assert "password" not in created.json()
            assert "hashed_password" not in created.json()

            correct = client.post(
                "/api/courier/login",
                json={"phone": "+79001234567", "password": "courier123"},
            )
            assert correct.status_code == 200, correct.text
            assert correct.json()["role"] == "courier"
            correct_v1 = client.post(
                "/api/v1/courier/login",
                json={"phone": "+79001234567", "password": "courier123"},
            )
            assert correct_v1.status_code == 200, correct_v1.text
            assert correct_v1.json()["role"] == correct.json()["role"]

            wrong = client.post(
                "/api/courier/login",
                json={"phone": "+79001234567", "password": "wrong12"},
            )
            assert wrong.status_code == 401, wrong.text

            missing = client.post(
                "/api/courier/login",
                json={"phone": "+79001234567"},
            )
            assert missing.status_code == 422, missing.text

            short = client.post(
                "/api/courier/login",
                json={"phone": "+79001234567", "password": "short"},
            )
            assert short.status_code == 422, short.text

    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
    print("courier password auth HTTP check: OK")
