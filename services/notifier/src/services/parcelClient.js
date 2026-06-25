'use strict';
const axios = require('axios');

const BASE = process.env.PARCEL_API_URL || 'http://parcel-api:3000';

const client = axios.create({
  baseURL: BASE,
  timeout: 5000
});

async function getById(id) {
  const res = await client.get(`/parcels/${id}`);
  return res.data;
}

async function patchStatus(id, status, notifiedAt) {
  const body = { status };
  if (notifiedAt) body.notifiedAt = notifiedAt;
  const res = await client.patch(`/parcels/${id}/status`, body);
  return res.data;
}

module.exports = { getById, patchStatus };
