'use strict';
const pool = require('./client');

const MAX_RETRIES = 15;
const RETRY_DELAY_MS = 3000;

async function waitForDb() {
  for (let i = 1; i <= MAX_RETRIES; i++) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (_err) {
      console.log(`[parcel-api] PostgreSQL not ready, retry ${i}/${MAX_RETRIES}...`);
      await new Promise(r => setTimeout(r, RETRY_DELAY_MS));
    }
  }
  throw new Error('PostgreSQL unreachable after retries');
}

async function runMigrations() {
  await waitForDb();

  await pool.query(`
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";

    CREATE TABLE IF NOT EXISTS parcels (
      id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
      tracking_code    VARCHAR(20)  UNIQUE NOT NULL,
      status           VARCHAR(30)  NOT NULL DEFAULT 'PENDING',
      sender_name      VARCHAR(255),
      recipient_name   VARCHAR(255),
      recipient_email  VARCHAR(255),
      recipient_address TEXT,
      recipient_lat    DECIMAL(10, 7),
      recipient_lng    DECIMAL(10, 7),
      weight_kg        DECIMAL(10, 2),
      notified_at      TIMESTAMP,
      created_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
      updated_at       TIMESTAMP    NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS delivery_events (
      id          UUID       PRIMARY KEY DEFAULT gen_random_uuid(),
      parcel_id   UUID       NOT NULL REFERENCES parcels(id) ON DELETE CASCADE,
      event_type  VARCHAR(50) NOT NULL,
      description TEXT,
      metadata    JSONB,
      created_at  TIMESTAMP  NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_parcels_tracking_code ON parcels(tracking_code);
    CREATE INDEX IF NOT EXISTS idx_delivery_events_parcel ON delivery_events(parcel_id);
  `);

  console.log('[parcel-api] Migrations OK');
}

module.exports = { runMigrations };
