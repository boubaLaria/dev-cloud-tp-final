'use strict';
const { Kafka } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'gps-ingestor',
  brokers: (process.env.REDPANDA_BROKERS || 'localhost:9092').split(','),
  retry: { retries: 8, initialRetryTime: 300 }
});

const producer = kafka.producer();
let connected = false;

async function connect() {
  if (!connected) {
    await producer.connect();
    connected = true;
    console.log('[gps-ingestor] Kafka producer connected');
  }
}

async function publishPosition(position) {
  await connect();
  await producer.send({
    topic: process.env.TOPIC_GPS_POSITIONS || 'gps.positions',
    messages: [{
      key: position.parcelId,
      value: JSON.stringify(position),
      timestamp: Date.now().toString()
    }]
  });
}

async function disconnect() {
  if (connected) {
    await producer.disconnect();
    connected = false;
  }
}

process.on('SIGTERM', disconnect);
process.on('SIGINT', disconnect);

module.exports = { publishPosition };
