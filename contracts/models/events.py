"""Cloud-Native Data Platform - Typed Event Models.

Validated against JSON Schema contracts under contracts/schemas/.
"""

from datetime import datetime
from enum import Enum
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class OrderStatus(str, Enum):
    CREATED = "CREATED"
    MERCHANT_ACCEPTED = "MERCHANT_ACCEPTED"
    RIDER_ASSIGNED = "RIDER_ASSIGNED"
    PICKED_UP = "PICKED_UP"
    DELIVERED = "DELIVERED"
    CANCELLED = "CANCELLED"


class PaymentMethod(str, Enum):
    LINE_PAY = "LINE_PAY"
    PROMPTPAY = "PROMPTPAY"
    CREDIT_CARD = "CREDIT_CARD"
    CASH_ON_DELIVERY = "CASH_ON_DELIVERY"


class DeliveryAddress(BaseModel):
    latitude: Optional[float] = Field(default=None, ge=-90.0, le=90.0)
    longitude: Optional[float] = Field(default=None, ge=-180.0, le=180.0)
    district: Optional[str] = None
    province: str = "Bangkok"


class OrderItem(BaseModel):
    item_id: str
    item_name: str
    quantity: int = Field(ge=1)
    price_baht: float = Field(ge=0.0)


class OrderLifecycleEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    event_id: str
    event_timestamp: datetime
    order_id: str
    order_status: OrderStatus
    merchant_id: str
    customer_id: str
    rider_id: Optional[str] = None
    total_amount_baht: float = Field(ge=0.0)
    payment_method: PaymentMethod
    delivery_address: Optional[DeliveryAddress] = None
    items: Optional[List[OrderItem]] = None


class RiderStatus(str, Enum):
    OFFLINE = "OFFLINE"
    AVAILABLE = "AVAILABLE"
    EN_ROUTE_TO_MERCHANT = "EN_ROUTE_TO_MERCHANT"
    WAITING_AT_MERCHANT = "WAITING_AT_MERCHANT"
    DELIVERING_ORDER = "DELIVERING_ORDER"


class RiderTelemetryEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    event_id: str
    event_timestamp: datetime
    rider_id: str
    latitude: float = Field(ge=-90.0, le=90.0)
    longitude: float = Field(ge=-180.0, le=180.0)
    geohash: str
    speed_kmh: Optional[float] = Field(default=None, ge=0.0)
    heading_degrees: Optional[float] = Field(default=None, ge=0.0, le=360.0)
    battery_level: Optional[int] = Field(default=None, ge=0, le=100)
    rider_status: RiderStatus
    current_order_id: Optional[str] = None


class DeadLetterPayload(BaseModel):
    quarantine_id: str
    source_topic: str
    error_type: str
    error_message: str
    failure_timestamp: datetime
    retry_count: int = 0
    raw_payload: str
    metadata: Optional[dict] = None
