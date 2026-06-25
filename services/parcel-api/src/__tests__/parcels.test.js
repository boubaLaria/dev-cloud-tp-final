'use strict';
jest.mock('../db/client', () => ({ query: jest.fn() }));

const request = require('supertest');
const express = require('express');
const pool = require('../db/client');
const parcelRouter = require('../routes/parcels');

const app = express();
app.use(express.json());
app.use('/parcels', parcelRouter);

describe('GET /parcels/:id', () => {
  it('returns 404 when parcel not found', async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).get('/parcels/nonexistent-id');
    expect(res.status).toBe(404);
  });

  it('returns parcel when found', async () => {
    const mock = { id: 'test-uuid', tracking_code: 'GL-TEST12', status: 'PENDING' };
    pool.query.mockResolvedValueOnce({ rows: [mock] });
    const res = await request(app).get('/parcels/test-uuid');
    expect(res.status).toBe(200);
    expect(res.body.tracking_code).toBe('GL-TEST12');
  });
});

describe('GET /parcels', () => {
  it('returns 400 without trackingCode param', async () => {
    const res = await request(app).get('/parcels');
    expect(res.status).toBe(400);
  });

  it('returns 404 when not found', async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).get('/parcels?trackingCode=GL-XXXXXX');
    expect(res.status).toBe(404);
  });
});

describe('POST /parcels', () => {
  it('creates a parcel and returns 201', async () => {
    const mock = { id: 'new-id', tracking_code: 'GL-ABCD12', status: 'PENDING', created_at: new Date() };
    pool.query
      .mockResolvedValueOnce({ rows: [mock] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app).post('/parcels').send({
      senderName: 'Alice', recipientName: 'Bob',
      recipientEmail: 'bob@test.com', recipientAddress: '1 rue Test',
      recipientLat: 48.8566, recipientLng: 2.3522, weightKg: 1.0
    });
    expect(res.status).toBe(201);
    expect(res.body.tracking_code).toMatch(/^GL-/);
  });
});

describe('PATCH /parcels/:id/status', () => {
  it('returns 400 for invalid status', async () => {
    const res = await request(app)
      .patch('/parcels/some-id/status')
      .send({ status: 'INVALID' });
    expect(res.status).toBe(400);
  });

  it('updates status successfully', async () => {
    const mock = { id: 'some-id', tracking_code: 'GL-TEST12', status: 'IN_TRANSIT', updated_at: new Date() };
    pool.query
      .mockResolvedValueOnce({ rows: [mock] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .patch('/parcels/some-id/status')
      .send({ status: 'IN_TRANSIT' });
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('IN_TRANSIT');
  });
});
