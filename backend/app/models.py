import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from app.utils import utc_now


class Base(DeclarativeBase):
    pass


class Admin(Base):
    __tablename__ = "admins"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True
    )
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="1"
    )
    is_superadmin: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="0"
    )
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utc_now
    )


class Courier(Base):
    __tablename__ = "couriers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    phone: Mapped[str] = mapped_column(String(20), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), default="active"
    )  # active / blocked
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utc_now
    )

    orders: Mapped[list["Order"]] = relationship(
        "Order", back_populates="courier", lazy="selectin"
    )


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_number: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    address: Mapped[str] = mapped_column(String(500), nullable=False)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    courier_fee: Mapped[float] = mapped_column(Float, default=0.0)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    cancel_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), default="available", index=True
    )  # available / taken / in_transit / delivered / cancelled
    recipient_phone: Mapped[str] = mapped_column(String(20), nullable=False, default='', server_default='')
    admin_phone: Mapped[str] = mapped_column(String(20), nullable=False, default='+79000000000', server_default='+79000000000')
    courier_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("couriers.id"), nullable=True, index=True
    )
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utc_now, index=True
    )
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utc_now, onupdate=utc_now
    )

    courier: Mapped[Optional["Courier"]] = relationship(
        "Courier", back_populates="orders", lazy="selectin"
    )
    history: Mapped[list["OrderHistory"]] = relationship(
        "OrderHistory", back_populates="order", lazy="selectin"
    )


class CourierLocation(Base):
    __tablename__ = "courier_locations"
    __table_args__ = (
        UniqueConstraint(
            "courier_id", name="uq_courier_locations_courier_id"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    courier_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("couriers.id"), nullable=False
    )
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utc_now, onupdate=utc_now
    )

    courier: Mapped[Courier] = relationship("Courier", backref="locations")


class OrderHistory(Base):
    __tablename__ = "order_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("orders.id"), nullable=False
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    changed_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utc_now
    )

    order: Mapped[Order] = relationship("Order", back_populates="history", lazy="selectin")
