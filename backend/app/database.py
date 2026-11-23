"""后端和数据库迁移共用的 PostgreSQL 连接配置。"""

import os
from pathlib import Path

from dotenv import dotenv_values
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, Engine
from sqlalchemy.exc import SQLAlchemyError

_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


def create_database_engine() -> Engine:
    """从仓库根目录的 .env 和进程环境读取配置，进程环境优先。"""
    settings = {**dotenv_values(_ENV_FILE, interpolate=False), **os.environ}
    password = settings.get("POSTGRES_PASSWORD")
    if not password:
        raise ValueError("请在环境变量或仓库根目录的 .env 中设置 POSTGRES_PASSWORD。")

    try:
        port = int(settings.get("POSTGRES_PORT") or "5432")
        if not 1 <= port <= 65535:
            raise ValueError
    except ValueError:
        raise ValueError("POSTGRES_PORT 必须是 1 到 65535 的整数。") from None

    url = URL.create(
        "postgresql+psycopg",
        username=settings.get("POSTGRES_USER") or "course_video",
        password=password,
        host=settings.get("POSTGRES_HOST") or "127.0.0.1",
        port=port,
        database=settings.get("POSTGRES_DB") or "course_video",
    )
    return create_engine(url, pool_pre_ping=True, connect_args={"connect_timeout": 5})


def _main() -> None:
    try:
        engine = create_database_engine()
    except ValueError as error:
        raise SystemExit(str(error)) from None

    try:
        with engine.connect() as connection:
            print(connection.execute(text("SELECT 1")).scalar_one())
    except SQLAlchemyError:
        raise SystemExit("PostgreSQL 连接检查失败，请确认数据库已启动且连接参数正确。") from None
    finally:
        engine.dispose()


if __name__ == "__main__":
    _main()
