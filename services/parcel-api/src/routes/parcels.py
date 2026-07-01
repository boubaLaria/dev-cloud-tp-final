import random
import string

from fastapi import APIRouter, HTTPException, Query

from ..db.client import pool_manager, record_to_dict
from ..schemas import ParcelCreate, StatusUpdate

router = APIRouter()


def _gen_tracking_code() -> str:
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
    return f"GL-{suffix}"


@router.post("", status_code=201)
async def create_parcel(body: ParcelCreate):
    pool = await pool_manager.get_pool()
    code = _gen_tracking_code()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO parcels
              (tracking_code, sender_name, recipient_name,
               recipient_email, recipient_address, recipient_lat, recipient_lng)
            VALUES ($1,$2,$3,$4,$5,$6,$7)
            RETURNING *
            """,
            code,
            body.senderName,
            body.recipientName,
            body.recipientEmail,
            body.recipientAddress,
            body.recipientLat,
            body.recipientLng,
        )
        await conn.execute(
            "INSERT INTO delivery_events (parcel_id, event_type) VALUES ($1, 'CREATED')",
            row["id"],
        )
    return record_to_dict(row)


@router.get("")
async def list_parcels(trackingCode: str | None = Query(None)):
    pool = await pool_manager.get_pool()
    async with pool.acquire() as conn:
        if trackingCode:
            rows = await conn.fetch(
                "SELECT * FROM parcels WHERE tracking_code = $1", trackingCode.upper()
            )
            if not rows:
                raise HTTPException(status_code=404, detail="Parcel not found")
            return record_to_dict(rows[0])
        rows = await conn.fetch(
            "SELECT * FROM parcels ORDER BY created_at DESC LIMIT 50"
        )
    return [record_to_dict(r) for r in rows]


@router.get("/{parcel_id}")
async def get_parcel(parcel_id: str):
    pool = await pool_manager.get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM parcels WHERE id = $1::uuid", parcel_id
        )
    if not row:
        raise HTTPException(status_code=404, detail="Parcel not found")
    return record_to_dict(row)


@router.patch("/{parcel_id}/status")
async def update_status(parcel_id: str, body: StatusUpdate):
    pool = await pool_manager.get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                """
                UPDATE parcels
                SET status = $1, notified_at = COALESCE($2, notified_at), updated_at = NOW()
                WHERE id = $3::uuid
                RETURNING *
                """,
                body.status.value,
                body.notifiedAt,
                parcel_id,
            )
            if not row:
                raise HTTPException(status_code=404, detail="Parcel not found")
            await conn.execute(
                "INSERT INTO delivery_events (parcel_id, event_type) VALUES ($1, $2)",
                row["id"],
                body.status.value,
            )
    return record_to_dict(row)
