"""后端测试：覆盖 health 与 greeting 接口。"""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_greeting():
    resp = client.get("/api/v1/greeting")
    assert resp.status_code == 200
    body = resp.json()
    assert body["message"] == "Hello from Python backend"
    assert body["time"]


def test_greeting_method_not_allowed():
    resp = client.post("/api/v1/greeting")
    assert resp.status_code == 405
