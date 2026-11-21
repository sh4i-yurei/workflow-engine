"""Create checked copies of OpenRig's SQLite database."""

import argparse
from contextlib import closing
from datetime import datetime, timedelta, timezone
import lzma
import os
from pathlib import Path
import re
import shutil
import sqlite3
import sys
from urllib.parse import quote


COPY_NAME = re.compile(r"openrig-(\d{8}T\d{6}Z)\.sqlite\.xz\Z")
PARTIAL_NAME = re.compile(r"\.openrig-\d{8}T\d{6}Z\.sqlite(?:\.xz)?\.partial\Z")


class BackupFailure(Exception):
    """A failure with a message suitable for the command's error line."""


def positive_hours(value):
    try:
        hours = int(value)
    except ValueError:
        hours = 0
    if hours < 1:
        raise argparse.ArgumentTypeError("must be a whole number of hours, 1 or more")
    return hours


def copy_database(source_path, partial):
    uri = "file:" + quote(str(source_path.absolute()), safe="/") + "?mode=ro"
    try:
        with closing(sqlite3.connect(uri, uri=True)) as source:
            with closing(sqlite3.connect(partial)) as target:
                source.backup(target)
    except sqlite3.Error as error:
        raise BackupFailure(f"cannot read {source_path}: {error}") from error


def check_copy(partial):
    try:
        with closing(sqlite3.connect(partial)) as copy:
            results = copy.execute("PRAGMA integrity_check").fetchall()
    except sqlite3.DatabaseError as error:
        raise BackupFailure(
            f"the copy failed PRAGMA integrity_check: {error}"
        ) from error
    if results != [("ok",)]:
        raise BackupFailure(f"the copy failed PRAGMA integrity_check: {results[0][0]}")


def prune(dest, now, keep_hours):
    removed = 0
    cutoff = now - timedelta(hours=keep_hours)
    for path in dest.iterdir():
        if not path.is_file():
            continue
        if PARTIAL_NAME.fullmatch(path.name):
            path.unlink()
            removed += 1
            continue
        match = COPY_NAME.fullmatch(path.name)
        if match is None:
            continue
        try:
            made = datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ").replace(
                tzinfo=timezone.utc
            )
        except ValueError:
            continue
        if made < cutoff:
            path.unlink()
            removed += 1
    return removed


def main(argv=None):
    parser = argparse.ArgumentParser(prog="openrig-backup")
    parser.add_argument(
        "--db", type=Path, default=Path.home() / ".openrig/openrig.sqlite"
    )
    parser.add_argument(
        "--dest", type=Path, default=Path.home() / ".openrig/backups/db"
    )
    parser.add_argument("--keep-hours", type=positive_hours, default=48)
    args = parser.parse_args(argv)
    db = args.db.expanduser()
    dest = args.dest.expanduser()
    now = datetime.now(timezone.utc)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    partial = dest / f".openrig-{stamp}.sqlite.partial"
    compressed = dest / f".openrig-{stamp}.sqlite.xz.partial"
    final = dest / f"openrig-{stamp}.sqlite.xz"
    succeeded = False
    try:
        dest.mkdir(parents=True, exist_ok=True)
        copy_database(db, partial)
        check_copy(partial)
        with partial.open("rb") as original, lzma.open(compressed, "wb") as output:
            shutil.copyfileobj(original, output)
        os.replace(compressed, final)
        partial.unlink()
        succeeded = True
        removed = prune(dest, now, args.keep_hours)
        print(
            f"openrig-backup: wrote {final} ({final.stat().st_size} bytes), removed {removed} old files"
        )
        return 0
    except BackupFailure as error:
        print(f"openrig-backup: backup failed: {error}", file=sys.stderr)
        return 1
    except OSError as error:
        print(
            f"openrig-backup: backup failed: cannot write to {dest}: {error.strerror}",
            file=sys.stderr,
        )
        return 1
    finally:
        if not succeeded and dest.is_dir():
            partial.unlink(missing_ok=True)
            compressed.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
