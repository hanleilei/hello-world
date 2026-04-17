def test_create_item(test_client):
    resp = test_client.http.post(
        "/items",
        headers={"Content-Type": "application/json"},
        body='{"name": "widget", "description": "a small widget"}',
    )
    assert resp.status_code == 201
    data = resp.json_body
    assert data["name"] == "widget"
    assert data["description"] == "a small widget"
    assert "id" in data


def test_list_items_empty(test_client):
    resp = test_client.http.get("/items")
    assert resp.status_code == 200
    assert resp.json_body == []


def test_list_items(test_client):
    test_client.http.post(
        "/items", headers={"Content-Type": "application/json"}, body='{"name": "a"}'
    )
    test_client.http.post(
        "/items", headers={"Content-Type": "application/json"}, body='{"name": "b"}'
    )
    resp = test_client.http.get("/items")
    assert resp.status_code == 200
    assert len(resp.json_body) == 2


def test_read_item(test_client):
    created = test_client.http.post(
        "/items", headers={"Content-Type": "application/json"}, body='{"name": "foo"}'
    ).json_body
    resp = test_client.http.get(f"/items/{created['id']}")
    assert resp.status_code == 200
    assert resp.json_body["name"] == "foo"


def test_read_item_not_found(test_client):
    resp = test_client.http.get("/items/does-not-exist")
    assert resp.status_code == 404


def test_delete_item(test_client):
    created = test_client.http.post(
        "/items",
        headers={"Content-Type": "application/json"},
        body='{"name": "to-delete"}',
    ).json_body
    resp = test_client.http.delete(f"/items/{created['id']}")
    assert resp.status_code == 204
    # Confirm it is gone
    assert test_client.http.get(f"/items/{created['id']}").status_code == 404


def test_delete_item_not_found(test_client):
    resp = test_client.http.delete("/items/does-not-exist")
    assert resp.status_code == 404


def test_create_item_missing_name(test_client):
    resp = test_client.http.post(
        "/items", headers={"Content-Type": "application/json"}, body="{}"
    )
    assert resp.status_code == 400
