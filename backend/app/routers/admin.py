from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import (
    create_access_token,
    get_current_admin,
    hash_password,
    verify_password,
)
from app.database import get_db
from app.models import Admin, Courier, CourierLocation, Order, OrderHistory
from app.schemas import (
    AdminLogin,
    AdminStats,
    CourierCreate,
    CourierOut,
    OrderCreate,
    OrderOut,
    Token,
)
from app.ws_manager import ws_manager

router = APIRouter(prefix="/api/admin", tags=["Admin"])


@router.post("/login", response_model=Token)
async def admin_login(body: AdminLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Admin).where(Admin.username == body.username))
    admin = result.scalar_one_or_none()
    if not admin or not verify_password(body.password, admin.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = create_access_token({"sub": admin.id, "role": "admin"})
    return Token(access_token=token, role="admin", user_id=admin.id)


@router.post("/couriers", response_model=CourierOut)
async def create_courier(
    body: CourierCreate,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    existing = await db.execute(select(Courier).where(Courier.phone == body.phone))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Phone already exists")
    courier = Courier(name=body.name, phone=body.phone)
    db.add(courier)
    await db.commit()
    await db.refresh(courier)
    await ws_manager.broadcast_to_admins("courier_created", {"id": courier.id, "name": courier.name})
    return courier


@router.get("/couriers", response_model=list[CourierOut])
async def list_couriers(
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    result = await db.execute(select(Courier).order_by(Courier.id))
    return result.scalars().all()


@router.patch("/couriers/{courier_id}/block", response_model=CourierOut)
async def block_courier(
    courier_id: int,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    result = await db.execute(select(Courier).where(Courier.id == courier_id))
    courier = result.scalar_one_or_none()
    if not courier:
        raise HTTPException(status_code=404, detail="Courier not found")
    courier.status = "blocked" if courier.status == "active" else "active"
    await db.commit()
    await db.refresh(courier)
    await ws_manager.broadcast_to_admins(
        "courier_status_changed",
        {"id": courier.id, "status": courier.status},
    )
    return courier


@router.post("/orders", response_model=OrderOut)
async def create_order(
    body: OrderCreate,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    existing = await db.execute(select(Order).where(Order.order_number == body.order_number))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Order number already exists")
    order = Order(
        order_number=body.order_number,
        address=body.address,
        price=body.price,
        courier_fee=body.courier_fee,
        description=body.description,
        recipient_phone=body.recipient_phone,
        admin_phone=body.admin_phone,
        latitude=body.latitude if body.latitude else 0.0,
        longitude=body.longitude if body.longitude else 0.0,
        status="available",
    )
    db.add(order)
    await db.commit()
    await db.refresh(order)

    history = OrderHistory(order_id=order.id, status="available")
    db.add(history)
    await db.commit()

    await ws_manager.broadcast_to_admins("order_created", {"id": order.id, "order_number": order.order_number})
    await ws_manager.broadcast_to_all_couriers("order_created", {"id": order.id, "order_number": order.order_number})
    return order


@router.get("/orders", response_model=list[OrderOut])
async def list_orders(
    status: Optional[str] = None,
    courier_id: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    stmt = select(Order)
    if status:
        stmt = stmt.where(Order.status == status)
    if courier_id:
        stmt = stmt.where(Order.courier_id == courier_id)
    stmt = stmt.order_by(Order.created_at.desc())
    result = await db.execute(stmt)
    return result.scalars().all()


@router.get("/orders/stats", response_model=AdminStats)
async def admin_stats(
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    total = await db.execute(select(func.count(Order.id)))
    available = await db.execute(select(func.count(Order.id)).where(Order.status == "available"))
    taken = await db.execute(select(func.count(Order.id)).where(Order.status == "taken"))
    in_transit = await db.execute(select(func.count(Order.id)).where(Order.status == "in_transit"))
    delivered = await db.execute(select(func.count(Order.id)).where(Order.status == "delivered"))

    total_couriers = await db.execute(select(func.count(Courier.id)))
    active_couriers = await db.execute(
        select(func.count(Courier.id)).where(Courier.status == "active")
    )

    return AdminStats(
        total_orders=total.scalar(),
        available=available.scalar(),
        taken=taken.scalar(),
        in_transit=in_transit.scalar(),
        delivered=delivered.scalar(),
        total_couriers=total_couriers.scalar(),
        active_couriers=active_couriers.scalar(),
    )


@router.get("/couriers/locations")
async def get_courier_locations(
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    stmt = select(CourierLocation, Courier.name).join(
        Courier, CourierLocation.courier_id == Courier.id
    )
    result = await db.execute(stmt)
    locations = []
    for loc, name in result:
        locations.append({
            "courier_id": loc.courier_id,
            "courier_name": name,
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "updated_at": loc.updated_at.isoformat() if loc.updated_at else "",
        })
    return locations


@router.patch("/orders/{order_id}/cancel")
async def cancel_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()

    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.status = "cancelled"

    history = OrderHistory(order_id=order.id, status="cancelled")
    db.add(history)

    await db.commit()

    await ws_manager.broadcast_to_admins(
        "order_cancelled",
        {"id": order.id, "order_number": order.order_number},
    )
    if order.courier_id:
        await ws_manager.send_to_courier(
            order.courier_id,
            "order_cancelled",
            {"id": order.id, "order_number": order.order_number},
        )

    return {"status": "cancelled"}


@router.delete("/orders/{order_id}")
async def delete_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    await db.execute(update(OrderHistory).where(OrderHistory.order_id == order_id).values(order_id=None))
    await db.delete(order)
    await db.commit()
    return {"ok": True}
