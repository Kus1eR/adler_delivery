from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_access_token, get_current_courier, verify_password
from app.database import get_db
from app.limiter import limiter
from app.models import Courier, CourierLocation, Order, OrderHistory
from app.schemas import CourierLogin, CourierStats, LocationUpdate, OrderOut, OrderStatusUpdate, Token
from app.services.order_service import can_transition, transition_order
from app.utils import normalize_phone, utc_now
from app.ws_manager import ws_manager

router = APIRouter(tags=["Courier"])


@router.post("/login", response_model=Token)
@limiter.limit("5/minute")
async def courier_login(request: Request, body: CourierLogin, db: AsyncSession = Depends(get_db)):
    normalized = normalize_phone(body.phone)
    result = await db.execute(select(Courier).where(Courier.phone == normalized))
    courier = result.scalar_one_or_none()
    if not courier:
        raise HTTPException(status_code=401, detail="Invalid phone")
    if not verify_password(body.password, courier.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid password")
    if courier.status == "blocked":
        raise HTTPException(status_code=403, detail="Courier blocked")
    token = create_access_token({"sub": courier.id, "role": "courier"})
    return Token(access_token=token, role="courier", user_id=courier.id)


@router.get("/orders/available", response_model=list[OrderOut])
async def available_orders(
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    result = await db.execute(
        select(Order)
        .where(Order.status == "available")
        .where(Order.is_deleted.is_(False))
        .order_by(Order.created_at.desc())
    )
    return result.scalars().all()


@router.post("/orders/{order_id}/take", response_model=OrderOut)
async def take_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    claim = await db.execute(
        update(Order)
        .where(
            Order.id == order_id,
            Order.status == "available",
            Order.is_deleted.is_(False),
        )
        .values(status="taken", courier_id=courier.id, updated_at=utc_now())
    )
    if claim.rowcount != 1:
        exists = await db.scalar(select(Order.id).where(Order.id == order_id))
        await db.rollback()
        if exists is None:
            raise HTTPException(status_code=404, detail="Order not found")
        raise HTTPException(status_code=409, detail="Order is not available")

    db.add(OrderHistory(order_id=order_id, status="taken"))
    await db.commit()
    order = await db.scalar(select(Order).where(Order.id == order_id))
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")

    await ws_manager.broadcast_to_admins(
        "order_taken", {"id": order.id, "courier_id": courier.id, "courier_name": courier.name}
    )
    await ws_manager.send_to_courier(courier.id, "order_updated", {"id": order.id, "status": "taken"})
    return order


@router.patch("/orders/{order_id}/status", response_model=OrderOut)
async def update_order_status(
    order_id: int,
    body: OrderStatusUpdate,
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.courier_id != courier.id:
        raise HTTPException(status_code=403, detail="Not your order")

    if not can_transition(order.status, body.status):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid transition from {order.status} to {body.status}",
        )

    await transition_order(order, body.status, db)
    await db.refresh(order)

    await ws_manager.broadcast_to_admins(
        "order_status_changed",
        {"id": order.id, "status": body.status, "courier_id": courier.id},
    )
    await ws_manager.send_to_courier(
        courier.id, "order_updated", {"id": order.id, "status": body.status}
    )
    return order


@router.get("/orders/my", response_model=list[OrderOut])
async def my_orders(
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    result = await db.execute(
        select(Order)
        .where(Order.courier_id == courier.id)
        .where(Order.status != "cancelled")
        .order_by(Order.created_at.desc())
    )
    return result.scalars().all()


@router.get("/orders/my/stats", response_model=CourierStats)
async def my_stats(
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    result = await db.execute(
        select(func.count(Order.id)).where(Order.courier_id == courier.id)
    )
    total_orders = result.scalar() or 0

    result = await db.execute(
        select(func.coalesce(func.sum(Order.courier_fee), 0)).where(
            Order.courier_id == courier.id, Order.status == "delivered"
        )
    )
    total_earned = float(result.scalar() or 0)

    today_start = utc_now().replace(hour=0, minute=0, second=0, microsecond=0)
    result = await db.execute(
        select(func.count(Order.id)).where(
            Order.courier_id == courier.id, Order.created_at >= today_start
        )
    )
    today_orders = result.scalar() or 0

    result = await db.execute(
        select(func.coalesce(func.sum(Order.courier_fee), 0)).where(
            Order.courier_id == courier.id,
            Order.status == "delivered",
            Order.created_at >= today_start,
        )
    )
    today_earned = float(result.scalar() or 0)

    return CourierStats(
        total_orders=total_orders,
        total_earned=total_earned,
        today_orders=today_orders,
        today_earned=today_earned,
    )


@router.get("/admin-phone")
async def get_admin_phone():
    return {"phone": "+79000000000"}


@router.post("/location")
async def update_location(
    body: LocationUpdate,
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    now = utc_now()
    values = {
        "courier_id": courier.id,
        "latitude": body.latitude,
        "longitude": body.longitude,
        "updated_at": now,
    }
    dialect_name = db.bind.dialect.name
    if dialect_name == "postgresql":
        stmt = postgresql_insert(CourierLocation).values(**values)
    elif dialect_name == "sqlite":
        stmt = sqlite_insert(CourierLocation).values(**values)
    else:
        raise HTTPException(status_code=500, detail="Unsupported database dialect")
    stmt = stmt.on_conflict_do_update(
        index_elements=[CourierLocation.courier_id],
        set_={key: value for key, value in values.items() if key != "courier_id"},
    )
    await db.execute(stmt)
    await db.commit()
    return {"status": "ok"}
