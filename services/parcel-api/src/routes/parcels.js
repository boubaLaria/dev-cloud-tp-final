'use strict';
const { Router } = require('express');
const pool = require('../db/client');

const router = Router();

const VALID_STATUSES = ['PENDING', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED'];

function generateTrackingCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = 'GL-';
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

// POST /parcels — créer un colis
router.post('/', async (req, res) => {
  try {
    const {
      senderName, recipientName, recipientEmail,
      recipientAddress, recipientLat, recipientLng, weightKg
    } = req.body;

    const trackingCode = generateTrackingCode();

    const result = await pool.query(
      `INSERT INTO parcels
         (tracking_code, sender_name, recipient_name, recipient_email,
          recipient_address, recipient_lat, recipient_lng, weight_kg)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING id, tracking_code, status, created_at`,
      [trackingCode, senderName, recipientName, recipientEmail,
       recipientAddress, recipientLat || null, recipientLng || null, weightKg || null]
    );

    const parcel = result.rows[0];

    await pool.query(
      `INSERT INTO delivery_events (parcel_id, event_type, description)
       VALUES ($1, 'CREATED', 'Colis créé')`,
      [parcel.id]
    );

    res.status(201).json(parcel);
  } catch (err) {
    console.error('[parcel-api] POST /parcels error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /parcels?trackingCode=GL-XXXX — recherche par code
router.get('/', async (req, res) => {
  const { trackingCode } = req.query;
  if (!trackingCode) {
    return res.status(400).json({ error: 'trackingCode query param is required' });
  }
  try {
    const result = await pool.query(
      'SELECT * FROM parcels WHERE tracking_code = $1',
      [trackingCode.toUpperCase()]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Parcel not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /parcels/:id — récupérer par UUID
router.get('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM parcels WHERE id = $1',
      [req.params.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Parcel not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PATCH /parcels/:id/status — mettre à jour le statut
router.patch('/:id/status', async (req, res) => {
  const { status, notifiedAt } = req.body;
  if (!VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: `Invalid status. Valid: ${VALID_STATUSES.join(', ')}` });
  }
  try {
    let query, values;
    if (notifiedAt) {
      query = `UPDATE parcels SET status=$1, notified_at=$2, updated_at=NOW()
               WHERE id=$3 RETURNING id, tracking_code, status, updated_at, notified_at`;
      values = [status, notifiedAt, req.params.id];
    } else {
      query = `UPDATE parcels SET status=$1, updated_at=NOW()
               WHERE id=$2 RETURNING id, tracking_code, status, updated_at`;
      values = [status, req.params.id];
    }

    const result = await pool.query(query, values);
    if (!result.rows.length) return res.status(404).json({ error: 'Parcel not found' });

    await pool.query(
      `INSERT INTO delivery_events (parcel_id, event_type, description)
       VALUES ($1, 'STATUS_CHANGE', $2)`,
      [req.params.id, `Statut changé en ${status}`]
    );

    res.json(result.rows[0]);
  } catch (err) {
    console.error('[parcel-api] PATCH status error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
