import datetime as dt
import lzma
import os
from pathlib import Path
import re
import runpy
import sqlite3
import sys
import time

import pytest

from tools import openrig_backup


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "tests/fixtures/openrig-0.7.19-schema.sql"
COPY_NAME = re.compile(r"^openrig-(\d{8}T\d{6}Z)\.sqlite\.xz$")
UTC = dt.timezone.utc


@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path / "home"))


def database(tmp_path):
    path = tmp_path / "openrig.sqlite"
    writer = sqlite3.connect(path)
    writer.execute("PRAGMA journal_mode=WAL")
    writer.execute("PRAGMA wal_autocheckpoint=0")
    writer.executescript(SCHEMA.read_text())
    writer.execute("PRAGMA user_version=7")
    for suffix in "abc":
        writer.execute(
            "INSERT INTO queue_items (qitem_id, ts_created, ts_updated, source_session, destination_session, state, body) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                f"qitem-{suffix}",
                "2026-11-21T00:00:00Z",
                "2026-11-21T00:00:00Z",
                "from",
                "to",
                "pending",
                "{}",
            ),
        )
    writer.commit()
    return path, writer


def copies(dest):
    return [p for p in dest.iterdir() if COPY_NAME.fullmatch(p.name)]


def read_copy(copy, tmp_path):
    unpacked = tmp_path / "unpacked.sqlite"
    unpacked.write_bytes(lzma.decompress(copy.read_bytes()))
    return sqlite3.connect(unpacked)


def old_copy(dest, hours, now):
    dest.mkdir(exist_ok=True)
    name = (now - dt.timedelta(hours=hours)).strftime(
        "openrig-%Y%m%dT%H%M%SZ.sqlite.xz"
    )
    path = dest / name
    path.write_bytes(b"old")
    return path


def run(db, dest, *extra):
    return openrig_backup.main(["--db", str(db), "--dest", str(dest), *extra])


def test_wal_copy_uses_utc_and_reports_exact_result(tmp_path, monkeypatch, capsys):
    db, writer = database(tmp_path)
    dest = tmp_path / "copies"
    assert (tmp_path / "openrig.sqlite-wal").stat().st_size > 0
    with monkeypatch.context() as change:
        change.setenv("TZ", "America/Chicago")
        time.tzset()
        try:
            start = dt.datetime.now(UTC).replace(microsecond=0)
            result = run(db, dest)
            end = dt.datetime.now(UTC).replace(microsecond=0)
        finally:
            pass
    time.tzset()
    writer.close()
    assert result == 0
    assert dest.is_dir()
    assert len(list(dest.iterdir())) == 1
    copy = copies(dest)[0]
    stamp = dt.datetime.strptime(
        COPY_NAME.fullmatch(copy.name).group(1), "%Y%m%dT%H%M%SZ"
    ).replace(tzinfo=UTC)
    assert start <= stamp <= end
    with read_copy(copy, tmp_path) as saved:
        assert saved.execute(
            "SELECT qitem_id FROM queue_items ORDER BY qitem_id"
        ).fetchall() == [("qitem-a",), ("qitem-b",), ("qitem-c",)]
        assert saved.execute("PRAGMA user_version").fetchall() == [(7,)]
        assert saved.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
    assert capsys.readouterr() == (
        f"openrig-backup: wrote {copy} ({copy.stat().st_size} bytes), removed 0 old files\n",
        "",
    )


def test_open_transaction_is_excluded(tmp_path):
    db, writer = database(tmp_path)
    other = sqlite3.connect(db)
    other.execute("BEGIN IMMEDIATE")
    other.execute(
        "INSERT INTO queue_items (qitem_id, ts_created, ts_updated, source_session, destination_session, state, body) VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("qitem-d", "t", "t", "from", "to", "pending", "{}"),
    )
    dest = tmp_path / "copies"
    assert run(db, dest) == 0
    assert dest.is_dir()
    with read_copy(copies(dest)[0], tmp_path) as saved:
        assert saved.execute("SELECT count(*) FROM queue_items").fetchall() == [(3,)]
    other.rollback()
    other.close()
    writer.close()


def test_missing_parent_preserves_old_copy(tmp_path, capsys):
    db, dest = tmp_path / "absent/openrig.sqlite", tmp_path / "copies"
    old = old_copy(dest, 49, dt.datetime.now(UTC))
    assert run(db, dest) == 1
    assert capsys.readouterr() == (
        "",
        f"openrig-backup: backup failed: cannot read {db}: unable to open database file\n",
    )
    assert not db.parent.exists()
    assert list(dest.iterdir()) == [old]


def test_missing_file_in_existing_parent_stays_missing(tmp_path, capsys):
    db, dest = tmp_path / "openrig.sqlite", tmp_path / "copies"
    assert run(db, dest) == 1
    assert capsys.readouterr() == (
        "",
        f"openrig-backup: backup failed: cannot read {db}: unable to open database file\n",
    )
    assert not db.exists()


def test_invalid_database_preserves_old_copy(tmp_path, capsys):
    db, dest = tmp_path / "openrig.sqlite", tmp_path / "copies"
    db.write_text("not a database at all, just text\n" * 200)
    old = old_copy(dest, 49, dt.datetime.now(UTC))
    assert run(db, dest) == 1
    assert capsys.readouterr() == (
        "",
        f"openrig-backup: backup failed: cannot read {db}: file is not a database\n",
    )
    assert list(dest.iterdir()) == [old]


def indexed_database(tmp_path, break_index):
    db = tmp_path / "indexed.sqlite"
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE q(id INTEGER PRIMARY KEY, k TEXT)")
        conn.execute("CREATE INDEX q_k ON q(k)")
        conn.executemany(
            "INSERT INTO q(k) VALUES (?)", [(f"key-{i:05d}",) for i in range(2000)]
        )
        if break_index == "definition":
            conn.execute("PRAGMA writable_schema=ON")
            conn.execute(
                "UPDATE sqlite_master SET sql='CREATE INDEX q_k ON q(id)' WHERE name='q_k'"
            )
            conn.execute("PRAGMA writable_schema=OFF")
        else:
            page = conn.execute(
                "SELECT rootpage FROM sqlite_master WHERE name='q_k'"
            ).fetchone()[0]
    if break_index == "page":
        with db.open("r+b") as file:
            file.seek((page - 1) * 4096 + 4096 - 1000)
            file.write(b"zzz-" * 250)
    return db


@pytest.mark.parametrize(
    "damage, message",
    [
        ("definition", "row 1 missing from index q_k"),
        ("page", "database disk image is malformed"),
    ],
)
def test_corrupt_copy_fails_without_pruning(tmp_path, capsys, damage, message):
    db, dest = indexed_database(tmp_path, damage), tmp_path / "copies"
    old = old_copy(dest, 49, dt.datetime.now(UTC))
    assert run(db, dest) == 1
    assert capsys.readouterr() == (
        "",
        f"openrig-backup: backup failed: the copy failed PRAGMA integrity_check: {message}\n",
    )
    assert list(dest.iterdir()) == [old]


def test_prunes_by_name_and_removes_leftovers_only_after_success(tmp_path, capsys):
    db, writer = database(tmp_path)
    dest, now = tmp_path / "copies", dt.datetime.now(UTC)
    kept30 = old_copy(dest, 30, now)
    gone49 = old_copy(dest, 49, now)
    kept2 = old_copy(dest, 2, now)
    gone100 = old_copy(dest, 100, now)
    for path, mtime in ((gone49, time.time()), (kept30, 0), (kept2, 0)):
        os.utime(path, (mtime, mtime))
    others = [
        dest / name
        for name in (
            "notes.txt",
            "openrig-20200101T000000Z.sqlite.gz",
            "openrig-20201399T000000Z.sqlite.xz",
            "openrig-20200101T000000Z.sqlite",
        )
    ]
    for path in others:
        path.write_bytes(b"keep")
    folder = dest / "old"
    folder.mkdir()
    nested = folder / "openrig-20200101T000000Z.sqlite.xz"
    nested.write_bytes(b"keep")
    leftovers = [
        dest / ".openrig-20200101T000000Z.sqlite.partial",
        dest / ".openrig-20200101T000000Z.sqlite.xz.partial",
    ]
    for path in leftovers:
        path.write_bytes(b"partial")
    assert run(db, dest) == 0
    writer.close()
    assert set(dest.iterdir()) == {kept30, kept2, *others, folder, *copies(dest)}
    assert nested.read_bytes() == b"keep"
    assert capsys.readouterr().out.endswith(", removed 4 old files\n")


def test_keep_hours_override(tmp_path):
    db, writer = database(tmp_path)
    dest, now = tmp_path / "copies", dt.datetime.now(UTC)
    recent = old_copy(dest, 0.5, now)
    expired = old_copy(dest, 2, now)
    assert run(db, dest, "--keep-hours", "1") == 0
    writer.close()
    assert recent.exists()
    assert not expired.exists()


def test_entrypoint_uses_home_and_ignores_working_folder(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    db_dir = home / ".openrig"
    db_dir.mkdir()
    source, writer = database(db_dir)
    writer.close()
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    monkeypatch.chdir(elsewhere)
    monkeypatch.setattr(sys, "argv", [str(ROOT / "tools/openrig_backup.py")])
    with pytest.raises(SystemExit) as result:
        runpy.run_path(str(ROOT / "tools/openrig_backup.py"), run_name="__main__")
    assert result.value.code == 0
    dest = home / ".openrig/backups/db"
    assert dest.is_dir()
    assert len(list(dest.iterdir())) == 1
    assert COPY_NAME.fullmatch(next(dest.iterdir()).name)
    assert list(elsewhere.iterdir()) == []


def test_relative_paths_with_uri_punctuation(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    folder = tmp_path / "my rig#1?x"
    folder.mkdir()
    db, writer = database(folder)
    writer.close()
    assert (
        openrig_backup.main(["--db", "my rig#1?x/openrig.sqlite", "--dest", "out dir"])
        == 0
    )
    dest = tmp_path / "out dir"
    assert dest.is_dir()
    assert len(copies(dest)) == 1
    assert set(tmp_path.iterdir()) == {folder, dest}
    with read_copy(copies(dest)[0], tmp_path) as saved:
        assert saved.execute("SELECT count(*) FROM queue_items").fetchall() == [(3,)]


@pytest.mark.parametrize("hours", ["0", "abc", "-3"])
def test_invalid_keep_hours_rejected_before_creating_destination(
    tmp_path, capsys, hours
):
    db, writer = database(tmp_path)
    dest = tmp_path / "copies"
    with pytest.raises(SystemExit) as result:
        run(db, dest, "--keep-hours", hours)
    writer.close()
    assert result.value.code == 2
    assert (
        capsys.readouterr().err.splitlines()[-1]
        == "openrig-backup: error: argument --keep-hours: must be a whole number of hours, 1 or more"
    )
    assert not dest.exists()


def test_stopped_database(tmp_path):
    db, writer = database(tmp_path)
    writer.close()
    assert not (tmp_path / "openrig.sqlite-wal").exists()
    dest = tmp_path / "copies"
    assert run(db, dest) == 0
    assert dest.is_dir()
    with read_copy(copies(dest)[0], tmp_path) as saved:
        assert saved.execute("SELECT count(*) FROM queue_items").fetchall() == [(3,)]


def test_destination_regular_file_is_preserved(tmp_path, capsys):
    db, writer = database(tmp_path)
    dest = tmp_path / "copies"
    dest.write_text("keep me")
    assert run(db, dest) == 1
    writer.close()
    assert capsys.readouterr() == (
        "",
        f"openrig-backup: backup failed: cannot write to {dest}: File exists\n",
    )
    assert dest.read_text() == "keep me"
