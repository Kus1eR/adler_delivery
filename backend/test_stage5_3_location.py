import asyncio

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import create_access_token
from app.database import get_db
from app.main import app
from app.models import Base, Courier, CourierLocation


async def main() -> None:
    constraints = {constraint.name for constraint in CourierLocation.__table__.constraints}
    assert "uq_courier_locations_courier_id" in constraints

    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    async with session_factory() as db:
        db.add(
            Courier(
                id=1,
                name="Courier",
                phone="+70000000001",
                hashed_password="x",
            )
        )
        await db.commit()

    async def override_db():
        async with session_factory() as db:
            yield db

    app.dependency_overrides[get_db] = override_db
    headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'courier'})}"
    }
    try:
        with TestClient(app) as client:
            first = client.post(
                "/api/courier/location",
                headers=headers,
                json={"latitude": 55.7, "longitude": 37.6},
            )
            second = client.post(
                "/api/courier/location",
                headers=headers,
                json={"latitude": 55.8, "longitude": 37.7},
            )
            assert first.status_code == 200, first.text
            assert second.status_code == 200, second.text
            invalid = client.post(
                "/api/v1/courier/location",
                headers=headers,
                json={"latitude": 91, "longitude": 181},
            )
            assert invalid.status_code == 422, invalid.text

        async with session_factory() as db:
            count = await db.scalar(select(func.count()).select_from(CourierLocation))
            location = await db.scalar(
                select(CourierLocation).where(CourierLocation.courier_id == 1)
            )
            assert count == 1
            assert location is not None
            assert location.latitude == 55.8
            assert location.longitude == 37.7

    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
    print("stage 5.3 location uniqueness checks: OK")
