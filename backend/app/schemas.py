import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


# --- Auth ---
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: int


class AdminLogin(BaseModel):
    username: str
    password: str


class AdminCreate(BaseModel):
    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=8)
    display_name: Optional[str] = Field(default=None, max_length=200)


class AdminOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    display_name: Optional[str]
    is_active: bool
    is_superadmin: bool
    created_at: datetime.datetime


class AdminStatusUpdate(BaseModel):
    is_active: bool


class CourierLogin(BaseModel):
    phone: str
    password: str = Field(min_length=6)


# --- Courier ---
class CourierCreate(BaseModel):
    name: str
    phone: str
    password: str = Field(min_length=6)


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
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class OrderUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    order_number: Optional[str] = None
    address: Optional[str] = None
    price: Optional[float] = Field(default=None, gt=0)
    courier_fee: Optional[float] = Field(default=None, ge=0)
    description: Optional[str] = None
    recipient_phone: Optional[str] = None
    admin_phone: Optional[str] = None
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def require_update(self):
        if not self.model_fields_set:
            raise ValueError("At least one field is required")
        nullable_fields = {"description"}
        if any(
            getattr(self, field) is None
            for field in self.model_fields_set - nullable_fields
        ):
            raise ValueError("Updated fields cannot be null")
        return self


class OrderOut(BaseModel):
    id: int
    order_number: str
    address: str
    price: float
    courier_fee: float
    description: Optional[str]
    cancel_reason: Optional[str] = None
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


class PaginatedOrders(BaseModel):
    items: list[OrderOut]
    total: int
    page: int
    per_page: int
    pages: int


# --- Location ---
class LocationUpdate(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
