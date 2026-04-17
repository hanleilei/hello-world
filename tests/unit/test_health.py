def test_health(test_client):
    resp = test_client.http.get("/health")
    assert resp.status_code == 200
    body = resp.json_body
    assert body["status"] == "ok"
    assert "uptime_seconds" in body


def test_root(test_client):
    resp = test_client.http.get("/")
    assert resp.status_code == 200
    assert resp.json_body["message"] == "hello-world"
