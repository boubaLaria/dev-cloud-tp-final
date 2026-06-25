'use strict';
const { Kafka } = require('kafkajs');
const { handlePosition } = require('../handlers/positionHandler');

const kafka = new Kafka({
  clientId: 'notifier',
  brokers: (process.env.REDPANDA_BROKERS || 'localhost:9092').split(','),
  retry: { retries: 12, initialRetryTime: 1000 }
});

const consumer = kafka.consumer({
  groupId: process.env.CONSUMER_GROUP_ID || 'notifier-group',
  heartbeatInterval: 3000,
  sessionTimeout: 30000
});

const dlqProducer = kafka.producer();

const MAX_ATTEMPTS = 3;

async function startConsumer() {
  await consumer.connect();
  await dlqProducer.connect();
  console.log('[notifier] Connected to Kafka');

  await consumer.subscribe({
    topic: process.env.TOPIC_GPS_POSITIONS || 'gps.positions',
    fromBeginning: false
  });

  await consumer.run({
    eachMessage: async ({ message }) => {
      let attempt = 0;
      while (attempt < MAX_ATTEMPTS) {
        try {
          await handlePosition(message);
          return;
        } catch (err) {
          attempt++;
          console.error(`[notifier] Handler error (attempt ${attempt}/${MAX_ATTEMPTS}):`, err.message);
          if (attempt < MAX_ATTEMPTS) {
            await new Promise(r => setTimeout(r, 500 * attempt));
          }
        }
      }

      // Envoyer en DLQ après MAX_ATTEMPTS
      try {
        await dlqProducer.send({
          topic: process.env.TOPIC_DLQ || 'gps.positions.dlq',
          messages: [{
            value: JSON.stringify({
              originalMessage: message.value?.toString(),
              errorReason: 'Max retry attempts reached',
              failedAt: new Date().toISOString(),
              attempt: MAX_ATTEMPTS
            })
          }]
        });
        console.warn('[notifier] Message envoyé en DLQ');
      } catch (dlqErr) {
        console.error('[notifier] DLQ send failed:', dlqErr.message);
      }
    }
  });

  console.log('[notifier] Consumer started — écoute sur gps.positions');
}

async function stopConsumer() {
  await consumer.disconnect();
  await dlqProducer.disconnect();
}

process.on('SIGTERM', stopConsumer);
process.on('SIGINT', stopConsumer);

module.exports = { startConsumer };
