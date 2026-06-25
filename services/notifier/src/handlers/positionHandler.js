'use strict';
const { distanceMeters } = require('../services/haversine');
const parcelClient = require('../services/parcelClient');
const { sendNotification } = require('../services/mailer');

const NOTIFY_RADIUS_M = parseInt(process.env.NOTIFY_RADIUS_METERS || '2000', 10);
const DELIVERED_RADIUS_M = 100;

async function handlePosition(message) {
  let position;
  try {
    position = JSON.parse(message.value.toString());
  } catch (_err) {
    console.error('[notifier] Failed to parse message, skipping');
    return;
  }

  const { parcelId, latitude, longitude } = position;
  if (!parcelId) return;

  let parcel;
  try {
    parcel = await parcelClient.getById(parcelId);
  } catch (err) {
    if (err.response?.status === 404) {
      console.warn(`[notifier] Parcel ${parcelId} not found in parcel-api`);
      return;
    }
    throw err;
  }

  if (parcel.status !== 'OUT_FOR_DELIVERY') return;
  if (!parcel.recipient_lat || !parcel.recipient_lng) return;

  const dist = distanceMeters(
    latitude, longitude,
    parseFloat(parcel.recipient_lat),
    parseFloat(parcel.recipient_lng)
  );

  console.log(`[notifier] ${parcel.tracking_code} — distance destination: ${Math.round(dist)}m`);

  if (dist < DELIVERED_RADIUS_M) {
    await parcelClient.patchStatus(parcel.id, 'DELIVERED');
    console.log(`[notifier] ${parcel.tracking_code} marqué DELIVERED`);
    return;
  }

  if (dist < NOTIFY_RADIUS_M && !parcel.notified_at) {
    await sendNotification(parcel);
    await parcelClient.patchStatus(parcel.id, 'OUT_FOR_DELIVERY', new Date().toISOString());
    console.log(`[notifier] Notification "5 min" envoyée pour ${parcel.tracking_code}`);
  }
}

module.exports = { handlePosition };
