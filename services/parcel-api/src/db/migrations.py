import asyncio
import os

import asyncpg


async def run_migrations():
    url = os.environ["DATABASE_URL"]
    conn = None
    for attempt in range(15):
        try:
            conn = await asyncpg.connect(url)
            break
        except Exception:
            if attempt == 14:
                raise
            await asyncio.sleep(3)

    await conn.execute("""
        CREATE EXTENSION IF NOT EXISTS pgcrypto;

        CREATE TABLE IF NOT EXISTS parcels (
            id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tracking_code    VARCHAR(10) UNIQUE NOT NULL,
            sender_name      TEXT NOT NULL,
            recipient_name   TEXT NOT NULL,
            recipient_email  TEXT NOT NULL,
            recipient_address TEXT NOT NULL,
            recipient_lat    DOUBLE PRECISION,
            recipient_lng    DOUBLE PRECISION,
            status           VARCHAR(20) NOT NULL DEFAULT 'PENDING',
            notified_at      TIMESTAMPTZ,
            created_at       TIMESTAMPTZ DEFAULT NOW(),
            updated_at       TIMESTAMPTZ DEFAULT NOW()
        );

        CREATE TABLE IF NOT EXISTS delivery_events (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            parcel_id   UUID REFERENCES parcels(id),
            event_type  VARCHAR(50) NOT NULL,
            payload     JSONB,
            created_at  TIMESTAMPTZ DEFAULT NOW()
        );
    """)
    await conn.close()
