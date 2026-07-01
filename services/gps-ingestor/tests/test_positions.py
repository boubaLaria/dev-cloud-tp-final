from unittest.mock import AsyncMock

import pytest
from httpx import ASGITransport, AsyncClient


@pytest.fixture
async def client(monkeypatch):
    from src.kafka import producer as producer_module

    monkeypatch.setattr(producer_module.producer, "start", AsyncMock())
    monkeypatch.setattr(producer_module.producer, "publish", AsyncMock())
    monkeypatch.setattr(producer_module.producer, "stop", AsyncMock())

    from src.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac


async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "service": "gps-ingestor"}


async def test_ingest_position_success(client):
    resp = await client.post(
        "/positions",
        json={"parcelId": "uuid-1", "latitude": 48.87, "longitude": 2.33},
    )
    assert resp.status_code == 202
    body = resp.json()
    assert body["status"] == "queued"
    assert "eventId" in body


async def test_ingest_position_invalid_lat(client):
    resp = await client.post(
        "/positions",
        json={"parcelId": "uuid-1", "latitude": 999, "longitude": 2.33},
    )
    assert resp.status_code == 422


async def test_ingest_position_invalid_lng(client):
    resp = await client.post(
        "/positions",
        json={"parcelId": "uuid-1", "latitude": 48.87, "longitude": 200},
    )
    assert resp.status_code == 422


async def test_ingest_position_missing_parcel_id(client):
    resp = await client.post("/positions", json={"latitude": 48.87, "longitude": 2.33})
    assert resp.status_code == 422


async def test_broker_error_returns_503(client, monkeypatch):
    from src.kafka import producer as producer_module

    monkeypatch.setattr(
        producer_module.producer, "publish", AsyncMock(side_effect=Exception("Kafka down"))
    )
    resp = await client.post(
        "/positions",
        json={"parcelId": "uuid-1", "latitude": 48.87, "longitude": 2.33},
    )
    assert resp.status_code == 503
    assert resp.json()["detail"] == "Message broker unavailable"


async def test_metrics_endpoint(client):
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert b"gps_positions_total" in resp.content
