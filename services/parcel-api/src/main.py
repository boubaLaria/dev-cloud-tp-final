import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from .db.client import pool_manager
from .db.migrations import run_migrations
from .metrics import REQUEST_COUNTER, REQUEST_DURATION
from .routes.parcels import router as parcels_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await run_migrations()
    yield
    await pool_manager.close()


app = FastAPI(title="parcel-api", version="1.0.0", lifespan=lifespan)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start
    REQUEST_COUNTER.labels(
        method=request.method,
        route=request.url.path,
        status_code=str(response.status_code),
    ).inc()
    REQUEST_DURATION.labels(method=request.method, route=request.url.path).observe(duration)
    return response


app.include_router(parcels_router, prefix="/parcels")


@app.get("/health")
async def health():
    return {"status": "ok", "service": "parcel-api"}


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
