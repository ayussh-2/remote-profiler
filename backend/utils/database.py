"""SQLite detection storage -- replaces Google Sheets for fast, local persistence."""

import os
import sqlite3
import threading
from datetime import datetime

DB_PATH = os.environ.get("DB_PATH", "detections.db")

_local = threading.local()


def _get_conn() -> sqlite3.Connection:
    if not hasattr(_local, "conn") or _local.conn is None:
        _local.conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        _local.conn.row_factory = sqlite3.Row
        _local.conn.execute("PRAGMA journal_mode=WAL")
        _local.conn.execute("PRAGMA synchronous=NORMAL")
    return _local.conn


def init_db():
    conn = _get_conn()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS detections (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp   INTEGER NOT NULL,
            datetime    TEXT NOT NULL,
            lat         REAL DEFAULT 0,
            lng         REAL DEFAULT 0,
            area_m2     REAL DEFAULT 0,
            depth_m     REAL DEFAULT 0,
            volume_m3   REAL DEFAULT 0,
            volume_liters REAL DEFAULT 0,
            confidence  REAL DEFAULT 0,
            severity    TEXT DEFAULT '',
            defect_type TEXT DEFAULT 'pothole'
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_timestamp ON detections(timestamp)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_latlon ON detections(lat, lng)")
    conn.commit()
    print(f"[DB] SQLite initialized: {DB_PATH}")


def insert_detection(payload: dict):
    conn = _get_conn()
    dt = datetime.fromtimestamp(payload["timestamp"]).strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        """INSERT INTO detections
           (timestamp, datetime, lat, lng, area_m2, depth_m, volume_m3,
            volume_liters, confidence, severity, defect_type)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            payload["timestamp"],
            dt,
            payload.get("lat", 0),
            payload.get("lng", 0),
            payload.get("area_m2", 0),
            payload.get("depth_m", 0),
            payload.get("volume_m3", 0),
            payload.get("volume_liters", 0),
            payload.get("confidence", 0),
            payload.get("severity", ""),
            payload.get("defect_type", "pothole"),
        ),
    )
    conn.commit()


def fetch_all_logs() -> list[dict]:
    conn = _get_conn()
    rows = conn.execute(
        "SELECT * FROM detections ORDER BY timestamp DESC"
    ).fetchall()
    return [dict(r) for r in rows]
