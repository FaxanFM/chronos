import argparse
import sqlite3
import time
from pathlib import Path


def create_fixture(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    try:
        connection.execute(
            """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL,
                level TEXT NOT NULL,
                target TEXT NOT NULL,
                feedback_log_body TEXT,
                module_path TEXT,
                file TEXT,
                line INTEGER,
                thread_id TEXT,
                process_uuid TEXT,
                estimated_bytes INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        rows = []
        for index in range(400):
            level = "INFO" if index % 5 == 0 else "TRACE"
            rows.append(
                (
                    index,
                    0,
                    level,
                    "fixture",
                    "x" * 2048,
                    2048,
                )
            )
        connection.executemany(
            """
            INSERT INTO logs (
                ts, ts_nanos, level, target, feedback_log_body, estimated_bytes
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        connection.commit()
        connection.execute("DELETE FROM logs WHERE id <= 200")
        connection.commit()
    finally:
        connection.close()


def verify_fixture(path: Path) -> None:
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        triggers = connection.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'"
        ).fetchone()[0]
        sequence = connection.execute(
            "SELECT seq FROM sqlite_sequence WHERE name='logs'"
        ).fetchone()[0]
        if triggers != 0:
            raise SystemExit(f"unexpected trigger count: {triggers}")
        if sequence != 400:
            raise SystemExit(f"unexpected sequence: {sequence}")
    finally:
        connection.close()


def create_partial_fixture(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    try:
        connection.execute("CREATE TABLE unrelated (id INTEGER PRIMARY KEY)")
        connection.commit()
    finally:
        connection.close()


def write_fixture(path: Path, duration: float) -> None:
    connection = sqlite3.connect(path, timeout=2)
    try:
        connection.execute("PRAGMA journal_mode=WAL")
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            connection.execute(
                """
                INSERT INTO logs (
                    ts, ts_nanos, level, target, feedback_log_body,
                    estimated_bytes
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (0, 0, "TRACE", "fixture-writer", "x" * 256, 256),
            )
            connection.commit()
            time.sleep(0.02)
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("create", "partial", "verify", "write"))
    parser.add_argument("path", type=Path)
    parser.add_argument("--duration", type=float, default=4.0)
    args = parser.parse_args()

    if args.action == "create":
        create_fixture(args.path)
    elif args.action == "partial":
        create_partial_fixture(args.path)
    elif args.action == "verify":
        verify_fixture(args.path)
    else:
        write_fixture(args.path, args.duration)


if __name__ == "__main__":
    main()
