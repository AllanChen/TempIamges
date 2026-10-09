"""Machine-local widget/version table. No Widget project files are stored here."""

import json
from hashlib import sha256
import os
from pathlib import Path
import re
import sqlite3
import sys
import uuid
from datetime import datetime, timezone


def config_dir() -> Path:
    return Path(os.environ.get("GLANCE_CLI_HOME", Path.home() / ".config" / "glance"))


def _secure_dir() -> Path:
    path = config_dir()
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name == "posix":
        path.chmod(0o700)
    return path


def connect() -> sqlite3.Connection:
    path = _secure_dir() / "widgets.sqlite"
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("""CREATE TABLE IF NOT EXISTS widgets (
        widget_id TEXT NOT NULL,
        version TEXT NOT NULL,
        manifest_path TEXT NOT NULL,
        code_path TEXT NOT NULL,
        python_path TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        server_status TEXT NOT NULL DEFAULT 'local',
        submission_id TEXT,
        last_request_at TEXT,
        last_error TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(widget_id, version)
    )""")
    columns = {row["name"] for row in db.execute("PRAGMA table_info(widgets)")}
    if "python_path" not in columns:
        db.execute("ALTER TABLE widgets ADD COLUMN python_path TEXT")
        db.execute("UPDATE widgets SET python_path=? WHERE python_path IS NULL",
                   (sys.executable,))
    db.commit()
    if os.name == "posix":
        path.chmod(0o600)
    return db


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def upsert(db: sqlite3.Connection, *, widget_id: str, version: str,
           manifest_path: str, code_path: str, enabled: bool,
           server_status: str, submission_id: str | None = None,
           python_path: str | None = None) -> None:
    python_path = python_path or sys.executable
    db.execute("""INSERT INTO widgets
        (widget_id,version,manifest_path,code_path,python_path,enabled,server_status,submission_id,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(widget_id,version) DO UPDATE SET
        manifest_path=excluded.manifest_path,code_path=excluded.code_path,python_path=excluded.python_path,
        enabled=excluded.enabled,server_status=excluded.server_status,
        submission_id=COALESCE(excluded.submission_id,widgets.submission_id),
        updated_at=excluded.updated_at""",
        (widget_id, version, manifest_path, code_path, python_path, int(enabled),
         server_status, submission_id, utc_now()))
    db.commit()


def update(db: sqlite3.Connection, widget_id: str, version: str, **fields: object) -> None:
    allowed = {"code_path", "python_path", "enabled", "server_status", "submission_id",
               "last_request_at", "last_error"}
    if not fields or set(fields) - allowed:
        raise ValueError("Invalid widget table fields")
    fields["updated_at"] = utc_now()
    columns = ",".join(f"{key}=?" for key in fields)
    db.execute(f"UPDATE widgets SET {columns} WHERE widget_id=? AND version=?",
               (*fields.values(), widget_id, version))
    db.commit()


def rows(db: sqlite3.Connection) -> list[dict]:
    return [dict(row) for row in db.execute(
        "SELECT * FROM widgets ORDER BY widget_id, version")]


def _version_key(value: str) -> tuple:
    """Choose one local code binding per Widget using natural version order."""
    return tuple((1, int(part)) if part.isdecimal() else (0, part.casefold())
                 for part in re.split(r"(\d+)", value))


def eligible(db: sqlite3.Connection, busy: set[str]) -> list[dict]:
    allowed = {"manual_review", "test_passed", "gray_release", "published"}
    selected: dict[str, dict] = {}
    for row in rows(db):
        widget_id = row["widget_id"]
        if not row["enabled"] or row["server_status"] not in allowed or widget_id in busy:
            continue
        previous = selected.get(widget_id)
        if previous is None or _version_key(row["version"]) > _version_key(previous["version"]):
            selected[widget_id] = row
    return [selected[widget_id] for widget_id in sorted(selected)]


def session_path() -> Path:
    return _secure_dir() / "session.json"


def worker_log_path() -> Path:
    return _secure_dir() / "worker.log"


def cache_manifest(manifest: dict) -> Path:
    """Keep server metadata outside the developer's Widget source folder."""
    directory = _secure_dir() / "manifests"
    directory.mkdir(mode=0o700, exist_ok=True)
    widget_id = str(uuid.UUID(str(manifest["id"])))
    version_hash = sha256(str(manifest["version"]).encode()).hexdigest()
    path = directory / f"{widget_id}-{version_hash}.json"
    temporary = directory / f".{path.name}.{os.getpid()}.tmp"
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(manifest, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return path


def save_session(session: dict) -> None:
    path = session_path()
    temporary = path.with_name(f"session.{os.getpid()}.tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(session, stream)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def read_session() -> dict | None:
    path = session_path()
    if not path.exists():
        return None
    try:
        session = json.loads(path.read_text(encoding="utf-8"))
        expiry = datetime.fromisoformat(session["expiresAt"].replace("Z", "+00:00"))
        return session if expiry > datetime.now(timezone.utc) else None
    except (ValueError, KeyError, TypeError):
        return None


def read_mock_token() -> str | None:
    """Use a temporary developer token without persisting a login session."""
    value = os.environ.get("GLANCE_MOCK_TOKEN", "").strip()
    if value:
        return value
    path = config_dir() / "mock-token"
    if path.is_file():
        return path.read_text(encoding="utf-8").strip() or None
    return None


def read_token() -> str | None:
    return read_mock_token() or (read_session() or {}).get("token")


def clear_session() -> None:
    session_path().unlink(missing_ok=True)
