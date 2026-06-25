'use strict';
const express = require('express');
const { register } = require('prom-client');
const { runMigrations } = require('./db/migrations');
const parcelRouter = require('./routes/parcels');
const { requestDurationMiddleware } = require('./metrics');

const app = express();
app.use(express.json());
app.use(requestDurationMiddleware);

app.use('/parcels', parcelRouter);

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'parcel-api' }));

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

const PORT = process.env.PORT || 3000;

async function main() {
  await runMigrations();
  app.listen(PORT, () => console.log(`[parcel-api] listening on ${PORT}`));
}

main().catch(err => { console.error(err); process.exit(1); });

module.exports = app; // for tests
