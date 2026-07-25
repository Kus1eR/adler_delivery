import codecs
import csv
import io
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import case, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import (
    create_access_token,
    get_current_admin,
    get_current_superadmin,
    hash_password,
    verify_password,
)
from app.database import get_db
from app.limiter import limiter
from app.models import Admin, Courier, CourierLocation, Order, OrderHistory
from app.schemas import (
    AdminLogin,
    AdminCreate,
    AdminOut,
    AdminStatusUpdate,
    AdminStats,
    CourierCreate,
    CourierOut,
    OrderCreate,
    OrderOut,
    OrderUpdate,
    PaginatedOrders,
    Token,
)
from app.services.order_service import transition_order
from app.utils import normalize_phone
from app.ws_manager import ws_manager

router = APIRouter(tags=["Admin"])

CSV_EXPORT_LIMIT = 10_000
CSV_FORMULA_PREFIXES = ("=", "+", "-", "@")


def csv_safe(value: object) -> object:
    if isinstance(value, str) and value.lstrip(" \t\r\n").startswith(CSV_FORMULA_PREFIXES):
        return "'" + value
    return value


def filtered_orders_query(
    status_filter: Optional[str],
    courier_id: Optional[int],
    search: Optional[str],
):
    stmt = select(Order).where(Order.is_deleted.is_(False))
    if status_filter:
        stmt = stmt.where(Order.status == status_filter)
    if courier_id:
        stmt = stmt.where(Order.courier_id == courier_id)
    if search:
        stmt = stmt.where(
            or_(
                Order.order_number.ilike(f"%{search}%"),
                Order.address.ilike(f"%{search}%"),
            )
        )
    return stmt.order_by(Order.created_at.desc())


@router.post("/login", response_model=Token)
@limiter.limit("5/minute")
async def admin_login(request: Request, body: AdminLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Admin).where(Admin.username == body.username))
    admin = result.scalar_one_or_none()
    if not admin or not verify_password(body.password, admin.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not admin.is_active:
        raise HTTPException(status_code=403, detail="Admin inactive")
    token = create_access_token({"sub": admin.id, "role": "admin"})
    return Token(access_token=token, role="admin", user_id=admin.id)


@router.get("/me", response_model=AdminOut)
async def current_admin(admin: Admin = Depends(get_current_admin)):
    return admin


@router.get("/admins", response_model=list[AdminOut])
async def list_admins(
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_superadmin),
):
    result = await db.execute(select(Admin).order_by(Admin.id))
    return result.scalars().all()


@router.post("/admins", response_model=AdminOut, status_code=201)
@limiter.limit("10/hour")
async def create_admin(
    request: Request,
    body: AdminCreate,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_superadmin),
):
    new_admin = Admin(
        username=body.username,
        hashed_password=hash_password(body.password),
        display_name=body.display_name,
        is_active=True,
        is_superadmin=False,
    )
    db.add(new_admin)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Username already exists")
    await db.refresh(new_admin)
    return new_admin


@router.patch("/admins/{admin_id}/status", response_model=AdminOut)
async def update_admin_status(
    admin_id: int,
    body: AdminStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_admin: Admin = Depends(get_current_superadmin),
):
    target = await db.scalar(
        select(Admin).where(Admin.id == admin_id).with_for_update()
    )
    if target is None:
        raise HTTPException(status_code=404, detail="Admin not found")
    if not body.is_active and target.id == current_admin.id:
        raise HTTPException(status_code=400, detail="Cannot deactivate yourself")
    if not body.is_active and target.is_superadmin and target.is_active:
        active_superadmins = (
            await db.execute(
                select(Admin.id)
                .where(
                    Admin.is_active.is_(True), Admin.is_superadmin.is_(True)
                )
                .with_for_update()
            )
        ).scalars().all()
        if len(active_superadmins) <= 1:
            raise HTTPException(
                status_code=400,
                detail="Cannot deactivate the last active superadmin",
            )
    target.is_active = body.is_active
    await db.commit()
    await db.refresh(target)
    return target


@router.post("/couriers", response_model=CourierOut)
async def create_courier(
    body: CourierCreate,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    normalized_phone = normalize_phone(body.phone)
    existing = await db.execute(select(Courier).where(Courier.phone == normalized_phone))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Phone already exists")
    courier = Courier(
        name=body.name,
        phone=normalized_phone,
        hashed_password=hash_password(body.password),
    )
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
    await db.flush()

    history = OrderHistory(order_id=order.id, status="available")
    db.add(history)
    await db.commit()
    await db.refresh(order)

    await ws_manager.broadcast_to_admins("order_created", {"id": order.id, "order_number": order.order_number})
    await ws_manager.broadcast_to_all_couriers("order_created", {"id": order.id, "order_number": order.order_number})
    return order


@router.get("/orders", response_model=PaginatedOrders)
async def list_orders(
    status: Optional[str] = None,
    courier_id: Optional[int] = None,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    stmt = filtered_orders_query(status, courier_id, search)

    total = await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    orders = (await db.execute(stmt.offset((page - 1) * per_page).limit(per_page))).scalars().all()

    return PaginatedOrders(
        items=[OrderOut.model_validate(o) for o in orders],
        total=total,
        page=page,
        per_page=per_page,
        pages=(total + per_page - 1) // per_page,
    )


@router.get("/orders/export.csv")
async def export_orders_csv(
    status: Optional[str] = None,
    courier_id: Optional[int] = None,
    search: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    stmt = filtered_orders_query(status, courier_id, search)
    total = await db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    if total > CSV_EXPORT_LIMIT:
        raise HTTPException(
            status_code=413,
            detail=f"Export is limited to {CSV_EXPORT_LIMIT} orders",
        )
    orders = (await db.execute(stmt)).scalars().all()
    output = io.StringIO(newline="")
    writer = csv.writer(output)
    writer.writerow(
        [
            "ID",
            "\u041d\u043e\u043c\u0435\u0440 \u0437\u0430\u043a\u0430\u0437\u0430",
            "\u0410\u0434\u0440\u0435\u0441",
            "\u0421\u0442\u0430\u0442\u0443\u0441",
            "\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c",
            "\u041e\u043f\u043b\u0430\u0442\u0430 \u043a\u0443\u0440\u044c\u0435\u0440\u0443",
            "\u0422\u0435\u043b\u0435\u0444\u043e\u043d \u043f\u043e\u043b\u0443\u0447\u0430\u0442\u0435\u043b\u044f",
            "\u0422\u0435\u043b\u0435\u0444\u043e\u043d \u0430\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440\u0430",
            "\u041a\u0443\u0440\u044c\u0435\u0440 ID",
            "\u0421\u043e\u0437\u0434\u0430\u043d",
        ]
    )
    for order in orders:
        writer.writerow(
            [csv_safe(value) for value in [
                order.id,
                order.order_number,
                order.address,
                order.status,
                order.price,
                order.courier_fee,
                order.recipient_phone,
                order.admin_phone,
                order.courier_id or "",
                order.created_at.isoformat(),
            ]]
        )
    content = codecs.BOM_UTF8 + output.getvalue().encode("utf-8")
    filename = f"orders-{date.today().isoformat()}.csv"
    return StreamingResponse(
        iter([content]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.patch("/orders/{order_id}", response_model=OrderOut)
async def update_order(
    order_id: int,
    body: OrderUpdate,
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    order = await db.scalar(
        select(Order).where(Order.id == order_id, Order.is_deleted.is_(False))
    )
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    updates = body.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(order, field, value)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Order number already exists")

    await db.refresh(order)
    event_data = {"id": order.id, "order_number": order.order_number}
    await ws_manager.broadcast_to_admins("order_updated", event_data)
    if order.courier_id:
        await ws_manager.send_to_courier(
            order.courier_id, "order_updated", event_data
        )
    return order


@router.get("/orders/stats", response_model=AdminStats)
async def admin_stats(
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    stats_query = select(
        func.count(Order.id).label("total_orders"),
        func.sum(case((Order.status == "available", 1), else_=0)).label("available"),
        func.sum(case((Order.status == "taken", 1), else_=0)).label("taken"),
        func.sum(case((Order.status == "in_transit", 1), else_=0)).label("in_transit"),
        func.sum(case((Order.status == "delivered", 1), else_=0)).label("delivered"),
    ).where(Order.is_deleted.is_(False))
    result = await db.execute(stats_query)
    row = result.one()

    courier_stats_query = select(
        func.count(Courier.id).label("total_couriers"),
        func.sum(case((Courier.status == "active", 1), else_=0)).label("active_couriers"),
    )
    courier_result = await db.execute(courier_stats_query)
    courier_row = courier_result.one()

    return AdminStats(
        total_orders=row.total_orders,
        available=row.available or 0,
        taken=row.taken or 0,
        in_transit=row.in_transit or 0,
        delivered=row.delivered or 0,
        total_couriers=courier_row.total_couriers,
        active_couriers=courier_row.active_couriers or 0,
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
    reason: str = Query(..., min_length=3, max_length=500),
    db: AsyncSession = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    result = await db.execute(select(Order).where(Order.id == order_id, Order.is_deleted.is_(False)))
    order = result.scalar_one_or_none()

    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    assigned_courier_id = order.courier_id
    order.cancel_reason = reason.strip()

    try:
        await transition_order(order, "cancelled", db)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    await ws_manager.broadcast_to_admins(
        "order_cancelled",
        {"id": order.id, "order_number": order.order_number},
    )
    if assigned_courier_id:
        await ws_manager.send_to_courier(
            assigned_courier_id,
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
    result = await db.execute(select(Order).where(Order.id == order_id, Order.is_deleted.is_(False)))
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    order.is_deleted = True
    if order.status != "cancelled":
        order.status = "cancelled"
        order.courier_id = None
        history = OrderHistory(order_id=order.id, status="cancelled")
        db.add(history)
    await db.commit()
    return {"ok": True}
