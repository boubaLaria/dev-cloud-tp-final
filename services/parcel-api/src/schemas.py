from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, EmailStr


class ParcelStatus(StrEnum):
    PENDING = "PENDING"
    IN_TRANSIT = "IN_TRANSIT"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY"
    DELIVERED = "DELIVERED"


class ParcelCreate(BaseModel):
    senderName: str
    recipientName: str
    recipientEmail: EmailStr
    recipientAddress: str
    recipientLat: float
    recipientLng: float


class StatusUpdate(BaseModel):
    status: ParcelStatus
    notifiedAt: datetime | None = None
