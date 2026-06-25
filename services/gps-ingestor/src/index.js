'use strict';
const express = require('express');
const { register } = require('prom-client');
const positionRouter = require('./routes/positions');

const app = express();
app.use(express.json());

app.use('/positions', positionRouter);
app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'gps-ingestor' }));
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`[gps-ingestor] listening on ${PORT}`));

module.exports = app;
