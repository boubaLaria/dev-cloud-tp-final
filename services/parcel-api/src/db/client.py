import os
import uuid

import asyncpg


class PoolManager:
    def __init__(self):
        self._pool: asyncpg.Pool | None = None

    async def get_pool(self) -> asyncpg.Pool:
        if self._pool is None:
            self._pool = await asyncpg.create_pool(os.environ["DATABASE_URL"])
        return self._pool

    async def close(self):
        if self._pool:
            await self._pool.close()
            self._pool = None


pool_manager = PoolManager()


def record_to_dict(record) -> dict:
    """Convert asyncpg Record to a JSON-serializable dict (UUID → str)."""
    result = {}
    for k, v in dict(record).items():
        if isinstance(v, uuid.UUID):
            result[k] = str(v)
        else:
            result[k] = v
    return result
