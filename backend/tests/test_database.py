import pytest

from app import database


@pytest.fixture
def env_file(tmp_path, monkeypatch):
    for key in (
        "POSTGRES_DB",
        "POSTGRES_USER",
        "POSTGRES_HOST",
        "POSTGRES_PORT",
        "POSTGRES_PASSWORD",
    ):
        monkeypatch.delenv(key, raising=False)
    path = tmp_path / ".env"
    monkeypatch.setattr(database, "_ENV_FILE", path)
    return path


def test_reads_dotenv_and_preserves_special_characters(env_file):
    example_value = "fixture:@ #${LITERAL}"
    env_file.write_text(f"POSTGRES_PASSWORD='{example_value}'\n", encoding="utf-8")

    url = database.create_database_engine().url

    assert url.drivername == "postgresql+psycopg"
    assert url.username == "course_video"
    assert url.host == "127.0.0.1"
    assert url.port == 5432
    assert url.database == "course_video"
    assert url.password == example_value


def test_process_environment_overrides_dotenv(env_file, monkeypatch):
    env_file.write_text("POSTGRES_PASSWORD=fixture\nPOSTGRES_PORT=5432\n", encoding="utf-8")
    monkeypatch.setenv("POSTGRES_PORT", "15432")
    monkeypatch.setenv("POSTGRES_DB", "course_video_test")

    url = database.create_database_engine().url

    assert url.port == 15432
    assert url.database == "course_video_test"


def test_requires_password(env_file):
    with pytest.raises(ValueError, match="POSTGRES_PASSWORD"):
        database.create_database_engine()


@pytest.mark.parametrize("port", ["invalid", "0", "65536"])
def test_rejects_invalid_port(env_file, monkeypatch, port):
    monkeypatch.setenv("POSTGRES_PASSWORD", "fixture")
    monkeypatch.setenv("POSTGRES_PORT", port)

    with pytest.raises(ValueError, match="POSTGRES_PORT"):
        database.create_database_engine()
