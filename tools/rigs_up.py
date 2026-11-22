#!/usr/bin/python3
"""Bring OpenRig teams back after a reboot."""

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys
import time


PS = ["rig", "ps", "--nodes", "-A", "--json"]
START = ["rig", "start", "--last"]
KERNEL = ["rig", "up", "kernel", "--existing"]


def positive_seconds(value):
    try:
        seconds = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError(
            "must be a number of seconds above 0"
        ) from None
    if not seconds > 0:
        raise argparse.ArgumentTypeError("must be a number of seconds above 0")
    return seconds


def nonnegative_seconds(value):
    try:
        seconds = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError(
            "must be a number of seconds, 0 or more"
        ) from None
    if not seconds >= 0:
        raise argparse.ArgumentTypeError("must be a number of seconds, 0 or more")
    return seconds


def read_seats():
    result = subprocess.run(
        PS, stdin=subprocess.DEVNULL, capture_output=True, text=True
    )
    if result.returncode:
        return None, result.returncode
    return json.loads(result.stdout), 0


def herdr_running():
    try:
        result = subprocess.run(
            ["herdr", "status", "server", "--json"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
    except (OSError, UnicodeError):
        return False
    if result.returncode:
        return False
    try:
        status = json.loads(result.stdout)
    except ValueError:
        return False
    return isinstance(status, dict) and status.get("running") is True


def down_seats(seats, rig=None):
    return [
        seat
        for seat in seats
        if not seat["intentionallyStopped"]
        and (
            rig is None
            or (
                seat["rigName"] == rig
                if rig == "kernel"
                else seat["rigName"] != "kernel"
            )
        )
        and (seat["sessionStatus"] != "running" or seat["startupStatus"] != "ready")
    ]


def daemon_error(code):
    return f"OpenRig's daemon isn't answering (rig ps --nodes -A --json exited {code})"


def fail(step, reason):
    print(f"rigs-up: failed at step {step}: {reason}", file=sys.stderr)
    return 1


def progress(message):
    print(f"rigs-up: {message}")


def main(argv=None):
    parser = argparse.ArgumentParser(prog="rigs-up")
    parser.add_argument(
        "--wait-seconds",
        type=positive_seconds,
        default=600,
        help="how long to wait for every seat, in seconds (default: %(default)g)",
    )
    parser.add_argument(
        "--poll-seconds",
        type=nonnegative_seconds,
        default=5,
        help="how often to check the seats, in seconds (default: %(default)g)",
    )
    options = parser.parse_args(argv)

    if os.environ.get("CONTAINER_ID") != "dev":
        progress("entering the dev container")
        sys.stdout.flush()
        path = str(Path(__file__).resolve())
        os.execvp(
            "distrobox",
            [
                "distrobox",
                "enter",
                "dev",
                "--",
                path,
                *(argv if argv is not None else sys.argv[1:]),
            ],
        )
        return 0

    seats, code = read_seats()
    if seats is None or down_seats(seats, "other"):
        progress("step 1 of 4: restoring the rigs that were running (rig start --last)")
        result = subprocess.run(START, stdin=subprocess.DEVNULL)
        if result.returncode:
            progress(
                f"rig start --last exited {result.returncode}; checking the seats anyway"
            )
        seats, code = read_seats()
        if seats is None:
            return fail(1, daemon_error(code))
    else:
        progress("step 1 of 4: every rig is already running")

    if down_seats(seats, "kernel"):
        progress("step 2 of 4: bringing the kernel back (rig up kernel --existing)")
        result = subprocess.run(KERNEL, stdin=subprocess.DEVNULL)
        if result.returncode:
            progress(
                f"rig up kernel --existing exited {result.returncode}; checking the seats anyway"
            )
    else:
        progress("step 2 of 4: the kernel is already running")

    deadline = time.monotonic() + options.wait_seconds
    waiting_announced = False
    while True:
        seats, code = read_seats()
        if seats is not None:
            down = down_seats(seats)
            if not down:
                stopped = sorted(
                    seat["canonicalSessionName"]
                    for seat in seats
                    if seat["intentionallyStopped"]
                )
                running = len(seats) - len(stopped)
                if stopped:
                    summary = f"{running} seats running, {len(stopped)} stopped on purpose ({', '.join(stopped)})"
                else:
                    summary = f"{running} seats running, none stopped on purpose"
                progress(f"step 3 of 4: {summary}")
                break
            if not waiting_announced:
                progress(f"step 3 of 4: waiting for {len(down)} seats to be running")
                waiting_announced = True
        if time.monotonic() >= deadline:
            if seats is None:
                return fail(3, daemon_error(code))
            names = ", ".join(sorted(seat["canonicalSessionName"] for seat in down))
            return fail(
                3,
                f"these seats aren't running after {options.wait_seconds:g} seconds: {names}",
            )
        time.sleep(options.poll_seconds)

    running = herdr_running()
    when = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if running:
        body = (
            f"rigs-up finished at {when}: {summary}. "
            "herdr is already running, so it was left as it is."
        )
    else:
        body = (
            f"rigs-up finished at {when}: {summary}. herdr is starting now. "
            "Please rename the herdr agents and check them."
        )
    queue = [
        "rig",
        "queue",
        "create",
        "--source",
        "rigs-up@host",
        "--destination",
        "main-lead@hq",
        "--tags",
        "project:openrig-team,item:startup-command",
        "--summary",
        "rigs-up: start done",
        "--body",
        body,
    ]
    result = subprocess.run(queue, stdin=subprocess.DEVNULL, capture_output=True)
    if result.returncode:
        if running:
            progress(
                f"step 4 of 4: couldn't tell main-lead@hq (rig queue create exited {result.returncode}); herdr is already running"
            )
        else:
            progress(
                f"step 4 of 4: couldn't tell main-lead@hq (rig queue create exited {result.returncode}); starting herdr anyway"
            )
    else:
        if running:
            progress(
                "step 4 of 4: told main-lead@hq the start is done; herdr is already running"
            )
        else:
            progress("step 4 of 4: told main-lead@hq the start is done; starting herdr")
    if running:
        return 0
    sys.stdout.flush()
    try:
        os.execvp("herdr", ["herdr"])
    except OSError as error:
        return fail(4, f"couldn't start herdr: {error.strerror}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
