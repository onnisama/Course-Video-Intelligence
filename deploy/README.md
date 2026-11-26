# 组内联调环境

从项目根目录进入 `deploy/`。复制 `.env.example` 为 `.env`，填入联调专用的 `POSTGRES_PASSWORD`，并将文件权限设为仅部署账号可读写。`INTEGRATION_PORT` 默认是 `18080`。`INTEGRATION_IMAGE_TAG` 用于标记这次应用镜像，部署时记录代码提交和镜像标签。

## 启动与验收

```bash
docker compose config --quiet
docker compose build
docker compose up -d --wait db
docker compose run --rm backend python -m app.database
docker compose run --rm backend python -m alembic upgrade head
docker compose run --rm backend python -m alembic current --check-heads
docker compose up -d --wait
docker compose ps
curl -fsS http://127.0.0.1:18080/
curl -fsS http://127.0.0.1:18080/api/health
```

三个服务应显示 `healthy`。数据库检查输出 `1`，迁移检查显示当前版本，`/api/health` 返回 `{"status":"ok"}`。若修改了 `INTEGRATION_PORT`，用相应端口访问。前端入口仅监听服务器回环地址。PostgreSQL 与 FastAPI 共用独立的内部网络。组内入口按团队确认的访问方式配置。

如果服务器无法拉取镜像，可在相同 CPU 架构且能访问镜像仓库的机器上构建，导出相同标签的前后端镜像及 PostgreSQL 镜像，再在目标机用 `docker image load` 导入。启动命令加 `--no-build --pull never`，一次性检查使用 `docker compose run --rm --pull never`。

## 停止与回滚

用 `docker compose down` 停止本项目，联调数据保存在本项目的命名卷中。恢复时使用同一份联调 `.env`，再运行 `docker compose up -d --wait`。版本回滚时使用此前验证通过的代码和镜像标签，确认数据库迁移与目标版本兼容后再切换，并复跑数据库和页面检查。
