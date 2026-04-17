"""
E2E smoke tests — run inside the test-runner container against a live
`chalice local` server backed by LocalStack DynamoDB.
Uses plain httpx so requests go through the real network / uvicorn stack.
"""

import httpx


def test_health(base_url):
    resp = httpx.get(f"{base_url}/health", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_root(base_url):
    resp = httpx.get(f"{base_url}/", timeout=10)
    assert resp.status_code == 200
    assert "hello-world" in resp.json()["message"]


def test_item_lifecycle(base_url):
    # Create
    resp = httpx.post(
        f"{base_url}/items",
        json={"name": "e2e-item", "description": "created by e2e test"},
        timeout=10,
    )
    assert resp.status_code == 201
    item = resp.json()
    assert item["name"] == "e2e-item"
    item_id = item["id"]

    # Read
    resp = httpx.get(f"{base_url}/items/{item_id}", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["id"] == item_id

    # List — item must appear
    resp = httpx.get(f"{base_url}/items", timeout=10)
    assert resp.status_code == 200
    ids = [i["id"] for i in resp.json()]
    assert item_id in ids

    # Delete
    resp = httpx.delete(f"{base_url}/items/{item_id}", timeout=10)
    assert resp.status_code == 204

    # Confirm deleted
    resp = httpx.get(f"{base_url}/items/{item_id}", timeout=10)
    assert resp.status_code == 404


def test_item_not_found(base_url):
    resp = httpx.get(f"{base_url}/items/does-not-exist", timeout=10)
    assert resp.status_code == 404


def test_create_item_missing_name(base_url):
    resp = httpx.post(f"{base_url}/items", json={}, timeout=10)
    assert resp.status_code == 400
