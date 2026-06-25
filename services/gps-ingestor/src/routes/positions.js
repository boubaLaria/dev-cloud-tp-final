'use strict';
const { Router } = require('express');
const { publishPosition } = require('../kafka/producer');
const { positionsTotal, positionsErrors } = require('../metrics');

const router = Router();

router.post('/', async (req, res) => {
  const { deliveryId, parcelId, latitude, longitude, speed, timestamp } = req.body;

  if (!parcelId || latitude == null || longitude == null) {
    return res.status(400).json({ error: 'parcelId, latitude and longitude are required' });
  }

  const position = {
    deliveryId: deliveryId || 'unknown',
    parcelId,
    latitude: parseFloat(latitude),
    longitude: parseFloat(longitude),
    speed: speed != null ? parseFloat(speed) : 0,
    timestamp: timestamp || new Date().toISOString()
  };

  try {
    await publishPosition(position);
    positionsTotal.inc();
    const eventId = `evt-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    res.status(202).json({ accepted: true, eventId });
  } catch (err) {
    positionsErrors.inc();
    console.error('[gps-ingestor] Kafka publish error:', err.message);
    res.status(500).json({ error: 'Failed to publish position' });
  }
});

module.exports = router;
