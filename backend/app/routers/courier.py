import re
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_access_token, get_current_courier
from app.database import get_db
from app.models import Courier, CourierLocation, Order, OrderHistory
from app.schemas import CourierLogin, CourierStats, LocationUpdate, OrderOut, OrderStatusUpdate, Token
from app.ws_manager import ws_manager

router = APIRouter(prefix="/api/courier", tags=["Courier"])


def _normalize_phone(phone: str) -> str:
    """Normalize to +7XXXXXXXXXX format. Accepts +7, 8, 7 prefixes with any separators."""
    digits = re.sub(r"\D", "", phone.strip())
    if digits.startswith("8") and len(digits) == 11:
        digits = "+7" + digits[1:]
    elif digits.startswith("7") and len(digits) == 11:
        digits = "+" + digits
    elif len(digits) == 10:
        digits = "+7" + digits
    return digits


@router.post("/login", response_model=Token)
async def courier_login(body: CourierLogin, db: AsyncSession = Depends(get_db)):
    normalized = _normalize_phone(body.phone)
    result = await db.execute(select(Courier))
    courier = next(
        (c for c in result.scalars().all() if _normalize_phone(c.phone) == normalized),
        None,
    )
    if not courier:
        raise HTTPException(status_code=401, detail="Invalid phone")
    if courier.status == "blocked":
        raise HTTPException(status_code=403, detail="Courier blocked")
    token = create_access_token({"sub": courier.id, "role": "courier"})
    return Token(access_token=token)


@router.get("/orders/available", response_model=list[OrderOut])
async def available_orders(
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    result = await db.execute(
        select(Order).where(Order.status == "available").order_by(Order.created_at.desc())
    )
    return result.scalars().all()


@router.post("/orders/{order_id}/take", response_model=OrderOut)
async def take_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    courier: Courier = Depends(get_current_courier),
):
    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.status != "available":
        raise HTTPException(status_code=400, detail="Order is not available")

    order.status = "taken"
    order.courier_id = courier.id
    await db.commit()
    await db.refresh(order)

    history = OrderHistory(order_id=order.id, status="taken")
    db.add(history)
    await db.commit()

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

    valid_transitions = {
        "taken": ["in_transit"],
        "in_transit": ["delivered"],
    }

    if order.status not in valid_transitions or body.status not in valid_transitions[order.status]:
        raise HTTPException(status_code=400, detail=f"Invalid transition from {order.status} to {body.status}")

    order.status = body.status
    await db.commit()
    await db.refresh(order)

    history = OrderHistory(order_id=order.id, status=body.status)
    db.add(history)
    await db.commit()

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

    today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
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
    stmt = select(CourierLocation).where(CourierLocation.courier_id == courier.id)
    result = await db.execute(stmt)
    location = result.scalar_one_or_none()

    if location:
        location.latitude = body.latitude
        location.longitude = body.longitude
        location.updated_at = datetime.utcnow()
    else:
        location = CourierLocation(
            courier_id=courier.id,
            latitude=body.latitude,
            longitude=body.longitude,
        )
        db.add(location)

    await db.commit()
    return {"status": "ok"}
