import asyncio
import json
import os

from aiokafka import AIOKafkaProducer


class KafkaProducer:
    def __init__(self):
        self._producer: AIOKafkaProducer | None = None

    async def start(self):
        brokers = os.environ.get("REDPANDA_BROKERS", "localhost:9092")
        self._producer = AIOKafkaProducer(
            bootstrap_servers=brokers,
            value_serializer=lambda v: json.dumps(v).encode(),
        )
        for attempt in range(10):
            try:
                await self._producer.start()
                return
            except Exception:
                if attempt == 9:
                    raise
                await asyncio.sleep(3)

    async def publish(self, topic: str, message: dict):
        if self._producer is None:
            raise RuntimeError("Producer not started")
        await self._producer.send_and_wait(topic, message)

    async def stop(self):
        if self._producer:
            await self._producer.stop()
            self._producer = None


producer = KafkaProducer()
