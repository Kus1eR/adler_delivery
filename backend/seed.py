"""Seed database with initial data."""
import asyncio

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import hash_password
from app.database import async_session
from app.models import Admin, Courier, Order, OrderHistory


async def seed():
    async with async_session() as db:
        existing = await db.execute(select(Admin).where(Admin.username == "admin"))
        if existing.scalar_one_or_none():
            print("Database already seeded, skipping.")
            return

        admin = Admin(
            username="admin",
            hashed_password=hash_password("admin123"),
        )
        db.add(admin)

        couriers_data = [
            ("Алексей Смирнов", "+79001111111"),
            ("Мария Петрова", "+79002222222"),
            ("Дмитрий Иванов", "+79003333333"),
        ]
        couriers = []
        for name, phone in couriers_data:
            courier = Courier(name=name, phone=phone)
            db.add(courier)
            couriers.append(courier)
        await db.commit()

        orders_data = [
            ("ORD-001", "ул. Ленина, д. 10, кв. 5", 450.0, "Позвонить за 10 минут, код домофона 5", "+71234567890", 55.7558, 37.6173),
            ("ORD-002", "ул. Тверская, д. 15", 320.0, "Оставить у двери", "+79876543210", 55.7600, 37.6200),
            ("ORD-003", "пр-т Мира, д. 22", 1500.0, "Грузовой лифт с торца здания", "+79111111111", 55.7800, 37.6300),
            ("ORD-004", "ул. Арбат, д. 1", 890.0, "Вход через арку, 2 этаж", "+79222222222", 55.7500, 37.5900),
            ("ORD-005", "ул. Новый Арбат, д. 8", 2500.0, "Позвонить по прибытии", "+79333333333", 55.7530, 37.5950),
            ("ORD-006", "Кутузовский пр-т, д. 30", 760.0, "Охрана на входе, нужен паспорт", "+79444444444", 55.7400, 37.5400),
            ("ORD-007", "ул. Покровка, д. 5", 1200.0, "Хрупкий груз", "+79555555555", 55.7600, 37.6500),
            ("ORD-008", "Садовое кольцо, д. 12", 600.0, "Срочно! Позвонить за 15 минут", "+79666666666", 55.7700, 37.6100),
        ]

        statuses = ["available", "available", "available", "available", "taken", "taken", "delivered", "delivered"]
        courier_ids = [None, None, None, None, couriers[0].id, couriers[1].id, couriers[2].id, couriers[2].id]

        for i, (num, addr, price, desc, phone, lat, lng) in enumerate(orders_data):
            fee = round(price * 0.5)
            order = Order(
                order_number=num,
                address=addr,
                price=price,
                courier_fee=fee,
                description=desc,
                recipient_phone=phone,
                admin_phone='+79000000000',
                latitude=lat,
                longitude=lng,
                status=statuses[i],
                courier_id=courier_ids[i],
            )
            db.add(order)
            await db.commit()
            await db.refresh(order)

            history = OrderHistory(order_id=order.id, status=statuses[i])
            db.add(history)

            if statuses[i] in ("taken", "delivered"):
                history2 = OrderHistory(
                    order_id=order.id,
                    status="available",
                    changed_at=order.created_at,
                )
                db.add(history2)
                if statuses[i] == "delivered":
                    history3 = OrderHistory(
                        order_id=order.id,
                        status="taken",
                        changed_at=order.created_at,
                    )
                    db.add(history3)
                    history4 = OrderHistory(
                        order_id=order.id,
                        status="in_transit",
                        changed_at=order.created_at,
                    )
                    db.add(history4)

        await db.commit()

    print("Database seeded successfully!")
    print("  Admin: admin / admin123")
    print("  Couriers: +79001111111, +79002222222, +79003333333")
    print("  Orders: 8 (4 available, 2 taken, 2 delivered)")


if __name__ == "__main__":
    asyncio.run(seed())
