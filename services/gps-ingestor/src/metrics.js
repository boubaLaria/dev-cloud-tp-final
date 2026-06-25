'use strict';
const client = require('prom-client');

client.collectDefaultMetrics({ prefix: 'gpsingestor_' });

const positionsTotal = new client.Counter({
  name: 'gps_positions_total',
  help: 'Total GPS positions received and published'
});

const positionsErrors = new client.Counter({
  name: 'gps_positions_errors_total',
  help: 'Total GPS positions that failed to publish'
});

module.exports = { positionsTotal, positionsErrors };
