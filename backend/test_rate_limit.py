import asyncio

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import hash_password
from app.database import get_db
from app.main import app
from app.models import Admin, Base


def main() -> None:
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def setup() -> None:
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        async with session_factory() as db:
            db.add(Admin(username="limited", hashed_password=hash_password("correct-password")))
            await db.commit()

    async def override_db():
        async with session_factory() as db:
            yield db

    asyncio.run(setup())
    app.dependency_overrides[get_db] = override_db
    try:
        with TestClient(app) as client:
            responses = [
                client.post(
                    "/api/v1/admin/login",
                    json={"username": "limited", "password": "wrong-password"},
                )
                for _ in range(6)
            ]
            assert [response.status_code for response in responses] == [401] * 5 + [429], [
                response.status_code for response in responses
            ]
    finally:
        app.dependency_overrides.clear()
        asyncio.run(engine.dispose())


if __name__ == "__main__":
    main()
    print("slowapi login rate limit check: OK")
