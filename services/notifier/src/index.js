'use strict';
const express = require('express');
const { startConsumer } = require('./kafka/consumer');

// Health endpoint minimal pour K8s liveness/readiness probes
const app = express();
app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'notifier' }));
app.listen(3003, () => console.log('[notifier] Health endpoint on 3003'));

startConsumer().catch(err => {
  console.error('[notifier] Consumer failed to start:', err);
  process.exit(1);
});
