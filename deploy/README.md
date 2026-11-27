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

## 手动发布到个人预览环境

[#37](https://github.com/onnisama/Course-Video-Intelligence/issues/37) 的首阶段使用 `course-video-integration` 项目及服务器回环地址 `127.0.0.1:18080`。工作流手动触发，检查该次 `main` 提交的 push CI 已成功，以完整 SHA 发布两张 GHCR 镜像，并按镜像摘要部署。组员入口 `18081` 的自动发布须在预览验收后由团队确认。

### 首次配置

1. 经团队确认后，由服务器管理员创建专用 `coursemind-deploy` 账号，使用独立 SSH 密钥。部署公钥由管理员添加，账号使用公钥认证，无其他登录方式、额外 sudo 权限或 `docker` 组成员资格。使用公钥的强制命令，仅运行预览脚本。

   ```text
   restrict,command="/usr/bin/sudo -n /usr/local/sbin/coursemind-preview-deploy" <专用部署公钥>
   ```

2. 管理员从已评审的 `main` 检出安装脚本。使用 `visudo -f /etc/sudoers.d/coursemind-preview` 保存下列单条规则，执行 `visudo -c` 核验。脚本、预览 Compose、`/opt/course-video-integration/source-path` 及其引用的检出目录均由管理员维护，部署账号无写权限。复用该目录原有 `.env` 和运行中的预览数据库，检查原预览首页与健康检查已经返回 HTTP 200。

   ```bash
   sudo install -o root -g root -m 0755 deploy/preview-deploy.sh /usr/local/sbin/coursemind-preview-deploy
   ```

   ```sudoers
   coursemind-deploy ALL=(root) NOPASSWD: /usr/local/sbin/coursemind-preview-deploy ""
   ```

3. 在 GitHub 创建 `preview` 环境，将部署分支限制为 `main`，按团队约定配置审核人。在环境的 Secrets 录入 `PREVIEW_SSH_HOST`（服务器地址）、`PREVIEW_SSH_KEY`（专用私钥）和 `PREVIEW_SSH_KNOWN_HOSTS`（经管理员核对指纹的服务器主机公钥，使用 `known_hosts` 格式）。保证 Actions 运行器可连接已有 SSH 服务，服务器可访问 GHCR。若镜像包已存在，需在其 **Manage Actions access** 确认本仓库有相应发布与拉取权限。[GitHub 环境配置](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) · [GitHub 容器仓库](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

### 触发与验收

合并后等待 `main` 的 CI 通过，再在 GitHub **Actions → 部署个人预览 → Run workflow** 选择 `main`，或运行 `gh workflow run deploy-preview.yml --ref main`。在对应运行记录核对 CI 链接、提交 SHA、两张镜像摘要与部署结果。如果 Compose 已修改，先由管理员审查并同步服务器的预览 Compose。

部署前用候选镜像运行 `SELECT 1` 和 `alembic current --check-heads`。切换后在正在运行的新后端容器中执行同样的只读检查，两项都通过才记录部署成功。切换后检查失败则回滚。如果发现数据库版本不匹配，由团队评审迁移后再重试。

用既有管理员 SSH 入口转发 `18080` 后，在浏览器打开 `http://127.0.0.1:18080/`，检查网页，以及 `/api/health` 的 HTTP 200 和 `{"status":"ok"}`。管理员在服务器对比部署前后的数据库容器 ID 和挂载卷。首次正式启用前，在隔离环境使用健康检查失败的测试镜像演练一次，核对工作流标记失败、上版镜像恢复、原数据库容器和卷仍在，以及首页与健康检查恢复 HTTP 200。

### 处理部署失败

切换前失败时清理本次临时目录，现有应用继续运行。切换后失败时用本机原有镜像重建前后端，回滚结果写入 Actions 日志。`/opt/course-video-integration/preview-images.yaml` 保存脚本当前选择的镜像，管理员手工执行 Compose 时应把它作为第二个 `-f` 文件。若日志显示回滚也失败，由管理员根据 Actions 日志确认上一版的镜像引用，检查数据库兼容性，再用同一项目、`.env` 和原卷恢复前后端。部署和回滚期间保留上一版镜像供本机使用。

## 停止与回滚

用 `docker compose down` 停止本项目，联调数据保存在本项目的命名卷中。恢复时使用同一份联调 `.env`，再运行 `docker compose up -d --wait`。版本回滚时使用此前验证通过的代码和镜像标签，确认数据库迁移与目标版本兼容后再切换，并复跑数据库和页面检查。
