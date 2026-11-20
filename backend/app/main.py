"""FastAPI 应用入口。

骨架阶段只提供健康检查接口，用于验证前端代理、本地启动和 CI 链路是否通畅。
业务接口按 v0.1 后续任务逐步加入。
"""

from fastapi import FastAPI

app = FastAPI(title="Course Video Intelligence API", version="0.1.0")


@app.get("/api/health")
def read_health() -> dict[str, str]:
    """返回后端服务存活状态。

    前端经 Vite 开发代理请求本接口，用于确认前后端连通性。
    """
    return {"status": "ok"}
