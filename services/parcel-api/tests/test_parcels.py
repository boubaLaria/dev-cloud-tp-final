import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

FAKE_ID = uuid.UUID("12345678-1234-5678-1234-567812345678")
FAKE_PARCEL = {
    "id": FAKE_ID,
    "tracking_code": "GL-TEST12",
    "sender_name": "Alice",
    "recipient_name": "Bob",
    "recipient_email": "bob@test.com",
    "recipient_address": "12 rue de la Paix, Paris",
    "recipient_lat": 48.87,
    "recipient_lng": 2.33,
    "status": "PENDING",
    "created_at": datetime(2026, 6, 25, 10, 0),
    "updated_at": datetime(2026, 6, 25, 10, 0),
    "notified_at": None,
}


@pytest.fixture
def mock_conn():
    conn = AsyncMock()
    conn.fetchrow = AsyncMock(return_value=FAKE_PARCEL)
    conn.fetch = AsyncMock(return_value=[FAKE_PARCEL])
    conn.execute = AsyncMock(return_value=None)
    return conn


@pytest.fixture
def mock_pool(mock_conn):
    ctx = MagicMock()
    ctx.__aenter__ = AsyncMock(return_value=mock_conn)
    ctx.__aexit__ = AsyncMock(return_value=False)
    pool = MagicMock()
    pool.acquire = MagicMock(return_value=ctx)
    pool.close = AsyncMock()
    return pool


@pytest.fixture
async def client(mock_pool, monkeypatch):
    import src.main as app_module
    from src.db import client as db_client

    monkeypatch.setattr(app_module, "run_migrations", AsyncMock())
    monkeypatch.setattr(db_client.pool_manager, "get_pool", AsyncMock(return_value=mock_pool))
    monkeypatch.setattr(db_client.pool_manager, "close", AsyncMock())

    async with AsyncClient(
        transport=ASGITransport(app=app_module.app), base_url="http://test"
    ) as ac:
        yield ac


async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
    assert resp.json()["service"] == "parcel-api"


async def test_create_parcel(client):
    resp = await client.post(
        "/parcels",
        json={
            "senderName": "Alice",
            "recipientName": "Bob",
            "recipientEmail": "bob@test.com",
            "recipientAddress": "12 rue de la Paix, Paris",
            "recipientLat": 48.87,
            "recipientLng": 2.33,
        },
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["tracking_code"] == "GL-TEST12"
    assert data["id"] == str(FAKE_ID)


async def test_create_parcel_invalid_email(client):
    resp = await client.post(
        "/parcels",
        json={
            "senderName": "Alice",
            "recipientName": "Bob",
            "recipientEmail": "not-an-email",
            "recipientAddress": "Paris",
            "recipientLat": 48.87,
            "recipientLng": 2.33,
        },
    )
    assert resp.status_code == 422


async def test_list_parcels_by_tracking_code(client):
    resp = await client.get("/parcels?trackingCode=GL-TEST12")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert data[0]["tracking_code"] == "GL-TEST12"


async def test_get_parcel(client):
    resp = await client.get(f"/parcels/{FAKE_ID}")
    assert resp.status_code == 200
    assert resp.json()["tracking_code"] == "GL-TEST12"


async def test_get_parcel_not_found(client, mock_conn):
    mock_conn.fetchrow.return_value = None
    resp = await client.get(f"/parcels/{FAKE_ID}")
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Parcel not found"


async def test_update_status(client):
    resp = await client.patch(
        f"/parcels/{FAKE_ID}/status", json={"status": "IN_TRANSIT"}
    )
    assert resp.status_code == 200
    assert resp.json()["tracking_code"] == "GL-TEST12"


async def test_update_status_invalid(client):
    resp = await client.patch(
        f"/parcels/{FAKE_ID}/status", json={"status": "INVALID_STATUS"}
    )
    assert resp.status_code == 422


async def test_metrics_endpoint(client):
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert b"http_requests_total" in resp.content
