import asyncio
import codecs
import csv
import io

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.auth import create_access_token, get_current_superadmin, hash_password
from app.database import get_db
from app.main import app
from app.routers.admin import csv_safe
from app.models import Admin, Base, Order


async def seed(session_factory: async_sessionmaker) -> None:
    async with session_factory() as db:
        db.add_all(
            [
                Admin(
                    id=1,
                    username="root",
                    hashed_password=hash_password("rootpass1"),
                    display_name="Главный",
                    is_active=True,
                    is_superadmin=True,
                ),
                Admin(
                    id=2,
                    username="regular",
                    hashed_password=hash_password("regular1"),
                    is_active=True,
                    is_superadmin=False,
                ),
                Admin(
                    id=3,
                    username="disabled",
                    hashed_password=hash_password("disabled1"),
                    is_active=False,
                    is_superadmin=False,
                ),
                Order(
                    order_number="CSV-1",
                    address="=HYPERLINK(https://example.invalid)",
                    price=100,
                    courier_fee=25,
                    status="available",
                    recipient_phone="+70000000001",
                    admin_phone="+70000000002",
                    latitude=1,
                    longitude=2,
                ),
                Order(
                    order_number="CSV-2",
                    address="ул. Пушкина, 2",
                    price=200,
                    courier_fee=50,
                    status="delivered",
                    latitude=3,
                    longitude=4,
                ),
                Order(
                    order_number="CSV-DELETED",
                    address="ул. Ленина, 3",
                    price=300,
                    courier_fee=75,
                    status="available",
                    latitude=5,
                    longitude=6,
                    is_deleted=True,
                ),
            ]
        )
        await db.commit()


async def main() -> None:
    assert csv_safe("\t=HYPERLINK(https://example.invalid)").startswith("'")
    assert csv_safe("\r+cmd|' /C calc'!A0").startswith("'")
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
    super_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 1, 'role': 'admin'})}"
    }
    regular_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': 2, 'role': 'admin'})}"
    }

    try:
        with TestClient(app) as client:
            for prefix in ("/api/admin", "/api/v1/admin"):
                me = client.get(f"{prefix}/me", headers=super_headers)
                assert me.status_code == 200, me.text
                assert me.json()["is_superadmin"] is True
                assert "hashed_password" not in me.json()

                forbidden = client.get(f"{prefix}/admins", headers=regular_headers)
                assert forbidden.status_code == 403, forbidden.text

                listed = client.get(f"{prefix}/admins", headers=super_headers)
                assert listed.status_code == 200, listed.text
                assert all("hashed_password" not in item for item in listed.json())

            created = client.post(
                "/api/v1/admin/admins",
                headers=super_headers,
                json={
                    "username": "second-root",
                    "password": "password8",
                    "display_name": "Второй",
                },
            )
            assert created.status_code == 201, created.text
            created_body = created.json()
            assert created_body["is_active"] is True
            assert created_body["is_superadmin"] is False
            assert "hashed_password" not in created_body

            too_short = client.post(
                "/api/v1/admin/admins",
                headers=super_headers,
                json={"username": "short", "password": "1234567"},
            )
            assert too_short.status_code == 422, too_short.text

            self_disable = client.patch(
                "/api/v1/admin/admins/1/status",
                headers=super_headers,
                json={"is_active": False},
            )
            assert self_disable.status_code == 400, self_disable.text

            app.dependency_overrides[get_current_superadmin] = lambda: Admin(
                id=999,
                username="external-root",
                hashed_password="x",
                is_active=True,
                is_superadmin=True,
            )
            last_superadmin = client.patch(
                "/api/v1/admin/admins/1/status",
                headers=super_headers,
                json={"is_active": False},
            )
            assert last_superadmin.status_code == 400, last_superadmin.text
            assert "last active superadmin" in last_superadmin.json()["detail"]
            del app.dependency_overrides[get_current_superadmin]

            deactivated = client.patch(
                f"/api/v1/admin/admins/{created_body['id']}/status",
                headers=super_headers,
                json={"is_active": False},
            )
            assert deactivated.status_code == 200, deactivated.text
            assert deactivated.json()["is_active"] is False

            inactive_login = client.post(
                "/api/v1/admin/login",
                json={"username": "disabled", "password": "disabled1"},
            )
            assert inactive_login.status_code == 403, inactive_login.text

            inactive_token = {
                "Authorization": f"Bearer {create_access_token({'sub': 3, 'role': 'admin'})}"
            }
            assert client.get("/api/v1/admin/me", headers=inactive_token).status_code == 403

            exported = client.get(
                "/api/v1/admin/orders/export.csv",
                headers=super_headers,
                params={"status": "available", "search": "HYPERLINK"},
            )
            assert exported.status_code == 200, exported.text
            assert exported.content.startswith(codecs.BOM_UTF8)
            assert "attachment;" in exported.headers["content-disposition"]
            rows = list(
                csv.reader(
                    io.StringIO(exported.content.decode("utf-8-sig"))
                )
            )
            assert rows[0][:4] == [
                "ID",
                "\u041d\u043e\u043c\u0435\u0440 \u0437\u0430\u043a\u0430\u0437\u0430",
                "\u0410\u0434\u0440\u0435\u0441",
                "\u0421\u0442\u0430\u0442\u0443\u0441",
            ], rows[0]
            assert len(rows) == 2, rows
            assert rows[1][1] == "CSV-1", rows[1]
            assert rows[1][2].startswith("'=HYPERLINK"), rows[1]
            assert "CSV-2" not in exported.text
            assert "CSV-DELETED" not in exported.text
    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
    print("stage 5.2 multi-admin and CSV checks: OK")
