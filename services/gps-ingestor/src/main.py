from contextlib import asynccontextmanager

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from .kafka.producer import producer
from .routes.positions import router as positions_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await producer.start()
    yield
    await producer.stop()


app = FastAPI(title="gps-ingestor", version="1.0.0", lifespan=lifespan)

app.include_router(positions_router, prefix="/positions")


@app.get("/health")
async def health():
    return {"status": "ok", "service": "gps-ingestor"}


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
