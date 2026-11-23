"""健康检查接口测试。

对应 Issue #7 验收标准：`GET /api/health` 返回 HTTP 200 和 `{"status": "ok"}`。
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_returns_200() -> None:
    """接口存在且返回成功状态码。"""
    response = client.get("/api/health")

    assert response.status_code == 200


def test_health_returns_ok_body() -> None:
    """响应体是约定的 JSON 结构，且不多带字段。"""
    response = client.get("/api/health")

    assert response.json() == {"status": "ok"}
