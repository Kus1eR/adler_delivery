import datetime
from typing import Optional

from pydantic import BaseModel, Field


# --- Auth ---
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: int


class AdminLogin(BaseModel):
    username: str
    password: str


class CourierLogin(BaseModel):
    phone: str


# --- Courier ---
class CourierCreate(BaseModel):
    name: str
    phone: str


class CourierOut(BaseModel):
    id: int
    name: str
    phone: str
    status: str
    created_at: datetime.datetime

    class Config:
        from_attributes = True


# --- Order ---
class OrderCreate(BaseModel):
    order_number: str
    address: str
    price: float = Field(gt=0)
    courier_fee: float = 0.0
    description: Optional[str] = None
    recipient_phone: str = ''
    admin_phone: str = '+79000000000'
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class OrderOut(BaseModel):
    id: int
    order_number: str
    address: str
    price: float
    courier_fee: float
    description: Optional[str]
    recipient_phone: str = ''
    admin_phone: str = '+79000000000'
    status: str
    courier_id: Optional[int]
    courier: Optional[CourierOut] = None
    latitude: float
    longitude: float
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True


class OrderStatusUpdate(BaseModel):
    status: str


# --- Stats ---
class CourierStats(BaseModel):
    total_orders: int
    total_earned: float
    today_orders: int
    today_earned: float


class AdminStats(BaseModel):
    total_orders: int
    available: int
    taken: int
    in_transit: int
    delivered: int
    total_couriers: int
    active_couriers: int


# --- Location ---
class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
