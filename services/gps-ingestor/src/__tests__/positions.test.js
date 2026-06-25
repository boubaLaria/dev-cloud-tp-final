'use strict';
jest.mock('../kafka/producer', () => ({ publishPosition: jest.fn().mockResolvedValue(undefined) }));

const request = require('supertest');
const express = require('express');
const positionRouter = require('../routes/positions');

const app = express();
app.use(express.json());
app.use('/positions', positionRouter);

describe('POST /positions', () => {
  it('returns 202 for valid position', async () => {
    const res = await request(app).post('/positions').send({
      parcelId: 'test-uuid',
      latitude: 48.8566,
      longitude: 2.3522,
      speed: 25.0
    });
    expect(res.status).toBe(202);
    expect(res.body.accepted).toBe(true);
    expect(res.body.eventId).toBeDefined();
  });

  it('returns 400 when parcelId is missing', async () => {
    const res = await request(app).post('/positions').send({
      latitude: 48.8566, longitude: 2.3522
    });
    expect(res.status).toBe(400);
  });

  it('returns 400 when coordinates are missing', async () => {
    const res = await request(app).post('/positions').send({ parcelId: 'test-uuid' });
    expect(res.status).toBe(400);
  });
});
