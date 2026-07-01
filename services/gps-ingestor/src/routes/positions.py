import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from ..kafka.producer import producer
from ..metrics import POSITIONS_ERRORS, POSITIONS_TOTAL
from ..schemas import PositionInput

router = APIRouter()
TOPIC = os.environ.get("TOPIC_GPS_POSITIONS", "gps.positions")


@router.post("", status_code=202)
async def ingest_position(body: PositionInput):
    event_id = str(uuid.uuid4())
    event = {
        "eventId": event_id,
        "parcelId": body.parcelId,
        "latitude": body.latitude,
        "longitude": body.longitude,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    try:
        await producer.publish(TOPIC, event)
        POSITIONS_TOTAL.inc()
    except Exception as exc:
        POSITIONS_ERRORS.inc()
        raise HTTPException(status_code=503, detail="Message broker unavailable") from exc
    return {"eventId": event_id, "status": "queued"}
