import json
import os
import re
import runpy
import sys
from pathlib import Path

import pytest

from tools import rigs_up


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/rigs_up"
ALL_UP = json.loads((FIXTURES / "rig-ps-nodes-all-up.json").read_text())
NEVER = json.loads((FIXTURES / "rig-ps-never-started-seat.json").read_text())
DAEMON_DOWN = {"error": True}
ARGS = ["--wait-seconds", "2", "--poll-seconds", "0"]
STOPPED = "advisor-lead@kernel"
NORMAL = "17 seats running, 1 stopped on purpose (advisor-lead@kernel)"
STEP3N = (
    "rigs-up: step 3 of 4: 17 seats running, 1 stopped on purpose "
    "(advisor-lead@kernel), 1 recorded and never started "
    "(never.owner@oq-rigsup-fields)"
)


def changed(names, **values):
    seats = json.loads(json.dumps(ALL_UP))
    for seat in seats:
        if seat["canonicalSessionName"] in names or seat["rigName"] in names:
            seat.update(values)
    return seats


@pytest.fixture
def fake_rig(tmp_path, monkeypatch):
    binary = tmp_path / "rig"
    binary.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "folder = Path(__file__).parent\n"
        "args = sys.argv[1:]\n"
        "tty = os.isatty(0)\n"
        "input_text = None if tty else sys.stdin.read()\n"
        "with (folder / 'calls').open('a') as log:\n"
        "    log.write(json.dumps({'args': args, 'tty': tty, 'stdin': input_text}) + '\\n')\n"
        "if args == ['ps', '--nodes', '-A', '--json']:\n"
        "    responses = json.loads((folder / 'responses').read_text())\n"
        "    count_file = folder / 'count'\n"
        "    count = int(count_file.read_text()) if count_file.exists() else 0\n"
        "    count_file.write_text(str(count + 1))\n"
        "    response = responses[min(count, len(responses) - 1)]\n"
        "    if isinstance(response, dict) and response.get('error'):\n"
        "        sys.stderr.write((folder / 'daemon-error').read_text())\n"
        "        sys.exit(1)\n"
        "    print(json.dumps(response))\n"
        "elif args == ['start', '--last']:\n"
        "    print('Daemon and kernel are up.')\n"
        "    sys.exit(int(os.environ.get('FAKE_START_RC', '0')))\n"
        "elif args == ['up', 'kernel', '--existing']:\n"
        "    print('  advisor.lead: awaiting-decision — no session started.', file=sys.stderr)\n"
        "    sys.exit(int(os.environ.get('FAKE_UP_RC', '1')))\n"
        "elif args == ['config', 'get', 'agents.operator_session']:\n"
        "    print(os.environ.get('FAKE_OPERATOR', 'main-lead@hq'))\n"
        "    sys.exit(int(os.environ.get('FAKE_CONFIG_RC', '0')))\n"
        "elif args[:2] == ['queue', 'create']:\n"
        "    print('Queue create request ID: qitem-20261122004930-1680a595ce40161d (not proof of persistence).')\n"
        "    sys.exit(int(os.environ.get('FAKE_QUEUE_RC', '0')))\n"
        "else:\n"
        "    sys.exit(3)\n"
    )
    binary.chmod(0o755)
    (tmp_path / "daemon-error").write_text(
        (FIXTURES / "rig-ps-daemon-down.stderr").read_text()
    )
    (tmp_path / "responses").write_text(json.dumps([ALL_UP]))
    monkeypatch.setenv("PATH", f"{tmp_path}:/usr/bin:/bin")
    monkeypatch.setenv("HOME", str(tmp_path / "empty-home"))
    (tmp_path / "empty-home").mkdir()
    monkeypatch.setenv("CONTAINER_ID", "dev")
    execs = []
    monkeypatch.setattr(
        os, "execvp", lambda file, args: execs.append([file, *args[1:]])
    )

    def set_responses(*responses):
        (tmp_path / "responses").write_text(json.dumps(responses))

    def calls():
        path = tmp_path / "calls"
        return (
            [json.loads(line) for line in path.read_text().splitlines()]
            if path.exists()
            else []
        )

    return set_responses, calls, execs


@pytest.fixture
def fake_herdr(fake_rig, tmp_path, monkeypatch):
    binary = tmp_path / "herdr"
    binary.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "folder = Path(__file__).parent\n"
        "tty = os.isatty(0)\n"
        "input_text = None if tty else sys.stdin.read()\n"
        "with (folder / 'herdr-calls').open('a') as log:\n"
        "    log.write(json.dumps({'args': sys.argv[1:], 'tty': tty, 'stdin': input_text}) + '\\n')\n"
        "sys.stdout.buffer.write((folder / 'herdr-reply').read_bytes())\n"
        "sys.exit(int(os.environ.get('FAKE_HERDR_RC', '0')))\n"
    )
    binary.chmod(0o755)

    def reply(value):
        if isinstance(value, bytes):
            (tmp_path / "herdr-reply").write_bytes(value)
        else:
            (tmp_path / "herdr-reply").write_text(value)

    def calls():
        path = tmp_path / "herdr-calls"
        return (
            [json.loads(line) for line in path.read_text().splitlines()]
            if path.exists()
            else []
        )

    reply((FIXTURES / "herdr-status-server-running.json").read_text())
    return reply, calls


def printed(capsys):
    out = capsys.readouterr()
    return out.out.splitlines(), out.err


STEP_LINES = [
    "rigs-up: step 1 of 4: every rig is already running",
    "rigs-up: step 2 of 4: the kernel is already running",
    f"rigs-up: step 3 of 4: {NORMAL}",
]


def test_running_herdr_is_left_alone(fake_herdr, fake_rig, capfd):
    _, herdr_calls = fake_herdr
    _, rig_calls, execs = fake_rig
    read_fd, write_fd = os.pipe()
    os.write(write_fd, b"y\n")
    os.close(write_fd)
    old_fd = os.dup(0)
    try:
        os.dup2(read_fd, 0)
        os.close(read_fd)
        assert rigs_up.main(ARGS) == 0
    finally:
        os.dup2(old_fd, 0)
        os.close(old_fd)
    out, err = capfd.readouterr()
    assert out.splitlines() == STEP_LINES + [
        "rigs-up: step 4 of 4: told main-lead@hq the start is done; herdr is already running"
    ]
    assert err == ""
    assert execs == []
    assert herdr_calls() == [
        {"args": ["status", "server", "--json"], "tty": False, "stdin": ""}
    ]
    body = rig_calls()[-1]["args"][-1]
    assert re.fullmatch(
        r"rigs-up finished at \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z: 17 seats running, 1 stopped on purpose \(advisor-lead@kernel\)\. herdr is already running, so it was left as it is\.",
        body,
    )


def test_not_running_herdr_starts(fake_herdr, fake_rig, capfd):
    reply, _ = fake_herdr
    reply((FIXTURES / "herdr-status-server-not-running.json").read_text())
    _, rig_calls, execs = fake_rig
    assert rigs_up.main(ARGS) == 0
    out, err = capfd.readouterr()
    assert out.splitlines() == STEP_LINES + [
        "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr"
    ]
    assert err == ""
    assert execs == [["herdr"]]
    assert rig_calls()[-1]["args"][-1].endswith(
        "herdr is starting now. Please rename the herdr agents and check them."
    )


@pytest.mark.parametrize(
    ("reply_text", "return_code"),
    [
        ((FIXTURES / "herdr-status-server-running.json").read_text(), 1),
        ("status: running\nversion: 0.9.5\n", 0),
        ("[]\n", 0),
        ('{"running": 1}\n', 0),
    ],
)
def test_herdr_status_other_results_start(
    fake_herdr, fake_rig, monkeypatch, reply_text, return_code
):
    reply, _ = fake_herdr
    reply(reply_text)
    monkeypatch.setenv("FAKE_HERDR_RC", str(return_code))
    _, _, execs = fake_rig
    assert rigs_up.main(ARGS) == 0
    assert execs == [["herdr"]]


def test_herdr_status_that_is_not_utf8_starts(fake_herdr, fake_rig):
    reply, _ = fake_herdr
    reply((FIXTURES / "herdr-status-server-running.json").read_text().encode("utf-16"))
    _, _, execs = fake_rig
    assert rigs_up.main(ARGS) == 0
    assert execs == [["herdr"]]


def test_running_herdr_queue_failure(fake_herdr, fake_rig, capfd, monkeypatch):
    _, _, execs = fake_rig
    monkeypatch.setenv("FAKE_QUEUE_RC", "1")
    assert rigs_up.main(ARGS) == 0
    out, err = capfd.readouterr()
    assert out.splitlines() == STEP_LINES + [
        "rigs-up: step 4 of 4: couldn't tell main-lead@hq (rig queue create exited 1); herdr is already running"
    ]
    assert err == ""
    assert execs == []


def test_all_up_and_queue_message(fake_rig, capsys):
    _, calls, execs = fake_rig
    assert rigs_up.main(ARGS) == 0
    actual = calls()
    assert [call["args"][:2] for call in actual] == [
        ["ps", "--nodes"],
        ["ps", "--nodes"],
        ["config", "get"],
        ["queue", "create"],
    ]
    assert actual[0]["args"] == actual[1]["args"] == ["ps", "--nodes", "-A", "--json"]
    queue = actual[3]["args"]
    assert queue[:-1] == [
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
    ]
    assert re.fullmatch(
        r"rigs-up finished at \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z: 17 seats running, 1 stopped on purpose \(advisor-lead@kernel\)\. herdr is starting now\. Please rename the herdr agents and check them\.",
        queue[-1],
    )
    assert execs == [["herdr"]]
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: every rig is already running",
            "rigs-up: step 2 of 4: the kernel is already running",
            f"rigs-up: step 3 of 4: {NORMAL}",
            "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
        ],
        "",
    )


def test_reboot_does_not_answer_advisor(fake_rig, capsys, monkeypatch):
    set_responses, calls, execs = fake_rig
    set_responses(
        DAEMON_DOWN,
        changed({"kernel"}, sessionStatus="exited", intentionallyStopped=False),
        changed({"backups-owner@platform"}, startupStatus="pending"),
        ALL_UP,
    )
    read_fd, write_fd = os.pipe()
    os.write(write_fd, b"y\n")
    os.close(write_fd)
    old_fd = os.dup(0)
    try:
        os.dup2(read_fd, 0)
        os.close(read_fd)
        assert rigs_up.main(ARGS) == 0
    finally:
        os.dup2(old_fd, 0)
        os.close(old_fd)
    actual = calls()
    assert [call["args"][:2] for call in actual] == [
        ["ps", "--nodes"],
        ["start", "--last"],
        ["ps", "--nodes"],
        ["up", "kernel"],
        ["ps", "--nodes"],
        ["ps", "--nodes"],
        ["config", "get"],
        ["queue", "create"],
    ]
    assert [(call["tty"], call["stdin"]) for call in actual] == [(False, "")] * 8
    assert execs == [["herdr"]]
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: restoring the rigs that were running (rig start --last)",
            "rigs-up: step 2 of 4: bringing the kernel back (rig up kernel --existing)",
            "rigs-up: rig up kernel --existing exited 1; checking the seats anyway",
            "rigs-up: step 3 of 4: waiting for 1 seats to be running",
            f"rigs-up: step 3 of 4: {NORMAL}",
            "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
        ],
        "",
    )


def test_daemon_never_answers(fake_rig, capsys):
    set_responses, calls, execs = fake_rig
    set_responses(DAEMON_DOWN)
    assert rigs_up.main(ARGS) == 1
    assert [x["args"] for x in calls()] == [
        ["ps", "--nodes", "-A", "--json"],
        ["start", "--last"],
        ["ps", "--nodes", "-A", "--json"],
    ]
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: restoring the rigs that were running (rig start --last)"
        ],
        "rigs-up: failed at step 1: OpenRig's daemon isn't answering (rig ps --nodes -A --json exited 1)\n",
    )
    assert execs == []


def test_wait_times_out_with_sorted_names(fake_rig, capsys):
    set_responses, calls, execs = fake_rig
    set_responses(
        changed(
            {"backups-owner@platform", "operations-owner@operations"},
            sessionStatus="exited",
        )
    )
    assert rigs_up.main(["--wait-seconds", "0.2", "--poll-seconds", "0.05"]) == 1
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: restoring the rigs that were running (rig start --last)",
            "rigs-up: step 2 of 4: the kernel is already running",
            "rigs-up: step 3 of 4: waiting for 2 seats to be running",
        ],
        "rigs-up: failed at step 3: these seats aren't running after 0.2 seconds: backups-owner@platform, operations-owner@operations\n",
    )
    assert not any(c["args"][:2] == ["queue", "create"] for c in calls())
    assert execs == []


def test_wait_times_out_after_daemon_fails(fake_rig, capsys):
    set_responses, _, execs = fake_rig
    set_responses(
        changed({"platform"}, sessionStatus="exited"),
        changed({"platform"}, sessionStatus="exited"),
        DAEMON_DOWN,
    )
    assert rigs_up.main(["--wait-seconds", "0.2", "--poll-seconds", "0.05"]) == 1
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: restoring the rigs that were running (rig start --last)",
            "rigs-up: step 2 of 4: the kernel is already running",
        ],
        "rigs-up: failed at step 3: OpenRig's daemon isn't answering (rig ps --nodes -A --json exited 1)\n",
    )
    assert execs == []


def test_another_intentionally_stopped_seat(fake_rig, capsys):
    set_responses, calls, _ = fake_rig
    set_responses(
        changed(
            {"staging-environment-owner@platform"},
            sessionStatus="exited",
            intentionallyStopped=True,
        )
    )
    assert rigs_up.main(ARGS) == 0
    assert [x["args"][:2] for x in calls()] == [
        ["ps", "--nodes"],
        ["ps", "--nodes"],
        ["config", "get"],
        ["queue", "create"],
    ]
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: every rig is already running",
            "rigs-up: step 2 of 4: the kernel is already running",
            "rigs-up: step 3 of 4: 16 seats running, 2 stopped on purpose (advisor-lead@kernel, staging-environment-owner@platform)",
            "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
        ],
        "",
    )


def test_crashed_advisor_restarts(fake_rig, capsys, monkeypatch):
    set_responses, calls, _ = fake_rig
    monkeypatch.setenv("FAKE_UP_RC", "0")
    set_responses(
        changed({STOPPED}, intentionallyStopped=False),
        changed({STOPPED}, sessionStatus="running", intentionallyStopped=False),
    )
    assert rigs_up.main(ARGS) == 0
    assert [x["args"][:2] for x in calls()] == [
        ["ps", "--nodes"],
        ["up", "kernel"],
        ["ps", "--nodes"],
        ["config", "get"],
        ["queue", "create"],
    ]
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: every rig is already running",
            "rigs-up: step 2 of 4: bringing the kernel back (rig up kernel --existing)",
            "rigs-up: step 3 of 4: 18 seats running, none stopped on purpose",
            "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
        ],
        "",
    )


@pytest.mark.parametrize("start_rc", [0, 1])
def test_platform_restores(fake_rig, capsys, monkeypatch, start_rc):
    set_responses, calls, execs = fake_rig
    monkeypatch.setenv("FAKE_START_RC", str(start_rc))
    set_responses(changed({"platform"}, sessionStatus="exited"), ALL_UP)
    assert rigs_up.main(ARGS) == 0
    assert [x["args"][:2] for x in calls()] == [
        ["ps", "--nodes"],
        ["start", "--last"],
        ["ps", "--nodes"],
        ["ps", "--nodes"],
        ["config", "get"],
        ["queue", "create"],
    ]
    expected = [
        "rigs-up: step 1 of 4: restoring the rigs that were running (rig start --last)"
    ]
    if start_rc:
        expected.append("rigs-up: rig start --last exited 1; checking the seats anyway")
    expected += [
        "rigs-up: step 2 of 4: the kernel is already running",
        f"rigs-up: step 3 of 4: {NORMAL}",
        "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
    ]
    assert printed(capsys) == (expected, "")
    assert execs == [["herdr"]]


def test_stopped_advisor_returns(fake_rig, capsys):
    set_responses, calls, _ = fake_rig
    set_responses(
        changed(
            {STOPPED},
            sessionStatus="running",
            startupStatus="ready",
            intentionallyStopped=False,
        )
    )
    assert rigs_up.main(ARGS) == 0
    assert [x["args"][:2] for x in calls()] == [
        ["ps", "--nodes"],
        ["ps", "--nodes"],
        ["config", "get"],
        ["queue", "create"],
    ]
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: every rig is already running",
            "rigs-up: step 2 of 4: the kernel is already running",
            "rigs-up: step 3 of 4: 18 seats running, none stopped on purpose",
            "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
        ],
        "",
    )


@pytest.mark.parametrize("container", [None, "kali"])
def test_host_reexec(fake_rig, capsys, monkeypatch, container):
    _, calls, execs = fake_rig
    if container is None:
        monkeypatch.delenv("CONTAINER_ID")
    else:
        monkeypatch.setenv("CONTAINER_ID", container)
    assert rigs_up.main(["--wait-seconds", "5"]) == 0
    assert execs == [
        [
            "distrobox",
            "enter",
            "dev",
            "--",
            str(ROOT / "tools/rigs_up.py"),
            "--wait-seconds",
            "5",
        ]
    ]
    assert calls() == []
    assert printed(capsys) == (["rigs-up: entering the dev container"], "")


def test_queue_failure_still_opens_herdr(fake_rig, capsys, monkeypatch):
    _, _, execs = fake_rig
    monkeypatch.setenv("FAKE_QUEUE_RC", "1")
    assert rigs_up.main(ARGS) == 0
    assert printed(capsys) == (
        [
            "rigs-up: step 1 of 4: every rig is already running",
            "rigs-up: step 2 of 4: the kernel is already running",
            f"rigs-up: step 3 of 4: {NORMAL}",
            "rigs-up: step 4 of 4: couldn't tell main-lead@hq (rig queue create exited 1); starting herdr anyway",
        ],
        "",
    )
    assert execs == [["herdr"]]


def test_herdr_missing(fake_rig, capsys, monkeypatch):
    def missing(file, args):
        raise FileNotFoundError(2, "No such file or directory")

    monkeypatch.setattr(os, "execvp", missing)
    assert rigs_up.main(ARGS) == 1
    assert (
        printed(capsys)[1]
        == "rigs-up: failed at step 4: couldn't start herdr: No such file or directory\n"
    )


@pytest.mark.parametrize(
    ("option", "value", "message"),
    [
        ("--wait-seconds", "0", "must be a number of seconds above 0"),
        ("--wait-seconds", "soon", "must be a number of seconds above 0"),
        ("--poll-seconds", "-1", "must be a number of seconds, 0 or more"),
        ("--poll-seconds", "often", "must be a number of seconds, 0 or more"),
    ],
)
def test_bad_arguments(fake_rig, capsys, option, value, message):
    _, calls, _ = fake_rig
    with pytest.raises(SystemExit) as error:
        rigs_up.main([option, value])
    assert error.value.code == 2
    assert (
        capsys.readouterr().err.splitlines()[-1]
        == f"rigs-up: error: argument {option}: {message}"
    )
    assert calls() == []


def test_help(fake_rig, capsys):
    with pytest.raises(SystemExit) as error:
        rigs_up.main(["--help"])
    assert error.value.code == 0
    output = " ".join(capsys.readouterr().out.split())
    assert "how long to wait for every seat, in seconds (default: 600)" in output
    assert "how often to check the seats, in seconds (default: 5)" in output


def test_entrypoint(fake_rig, monkeypatch):
    _, _, execs = fake_rig
    monkeypatch.setattr(sys, "argv", [str(ROOT / "tools/rigs_up.py"), *ARGS])
    with pytest.raises(SystemExit) as error:
        runpy.run_path(str(ROOT / "tools/rigs_up.py"), run_name="__main__")
    assert error.value.code == 0
    assert execs == [["herdr"]]


def test_exec_gets_full_argument_lists(fake_rig, monkeypatch):
    full = []
    monkeypatch.setattr(
        os, "execvp", lambda file, args: full.append([file, list(args)])
    )
    assert rigs_up.main(ARGS) == 0
    monkeypatch.delenv("CONTAINER_ID")
    assert rigs_up.main(["--wait-seconds", "5"]) == 0
    assert full == [
        ["herdr", ["herdr"]],
        [
            "distrobox",
            [
                "distrobox",
                "enter",
                "dev",
                "--",
                str(ROOT / "tools/rigs_up.py"),
                "--wait-seconds",
                "5",
            ],
        ],
    ]


def test_host_reexec_without_arguments_forwards_sys_argv(fake_rig, monkeypatch):
    full = []
    monkeypatch.setattr(
        os, "execvp", lambda file, args: full.append([file, list(args)])
    )
    monkeypatch.delenv("CONTAINER_ID")
    monkeypatch.setattr(
        sys, "argv", [str(ROOT / "tools/rigs_up.py"), "--wait-seconds", "7"]
    )
    assert rigs_up.main() == 0
    assert full == [
        [
            "distrobox",
            [
                "distrobox",
                "enter",
                "dev",
                "--",
                str(ROOT / "tools/rigs_up.py"),
                "--wait-seconds",
                "7",
            ],
        ]
    ]


def test_queue_output_stays_off_the_terminal(fake_rig, capfd):
    assert rigs_up.main(ARGS) == 0
    out, err = capfd.readouterr()
    assert out.splitlines() == [
        "rigs-up: step 1 of 4: every rig is already running",
        "rigs-up: step 2 of 4: the kernel is already running",
        f"rigs-up: step 3 of 4: {NORMAL}",
        "rigs-up: step 4 of 4: told main-lead@hq the start is done; starting herdr",
    ]
    assert err == ""


def test_never_started_beside_running_seats(fake_rig, capsys):
    set_responses, calls, _ = fake_rig
    set_responses(ALL_UP + [NEVER])
    assert rigs_up.main(ARGS) == 0
    lines, err = printed(capsys)
    assert STEP3N in lines
    assert err == ""
    assert not any(call["args"][:2] == ["start", "--last"] for call in calls())
    assert (
        STEP3N.removeprefix("rigs-up: step 3 of 4: ") + "." in calls()[-1]["args"][-1]
    )


def test_never_started_beside_down_seat(fake_rig, capsys):
    set_responses, calls, _ = fake_rig
    down = changed(
        {"openrig-team-owner@workflow-engine"},
        sessionStatus="exited",
        startupStatus="ready",
        lifecycleState="detached",
    )
    set_responses(down + [NEVER], ALL_UP + [NEVER])
    assert rigs_up.main(ARGS) == 0
    lines, err = printed(capsys)
    assert STEP3N in lines
    assert err == ""
    assert sum(call["args"] == ["start", "--last"] for call in calls()) == 1


def test_operator_address_from_config(fake_herdr, fake_rig, monkeypatch, capfd):
    _, rig_calls, execs = fake_rig
    monkeypatch.setenv("FAKE_OPERATOR", "main-operator@hq")
    read_fd, write_fd = os.pipe()
    os.write(write_fd, b"y\n")
    os.close(write_fd)
    old_fd = os.dup(0)
    try:
        os.dup2(read_fd, 0)
        os.close(read_fd)
        assert rigs_up.main(ARGS) == 0
    finally:
        os.dup2(old_fd, 0)
        os.close(old_fd)
    calls = rig_calls()
    queue = calls[-1]["args"]
    assert queue[queue.index("--destination") + 1] == "main-operator@hq"
    assert [
        call
        for call in calls
        if call["args"] == ["config", "get", "agents.operator_session"]
    ] == [
        {
            "args": ["config", "get", "agents.operator_session"],
            "tty": False,
            "stdin": "",
        }
    ]
    assert execs == []
    out, err = capfd.readouterr()
    assert err == ""
    assert out.splitlines()[-1] == (
        "rigs-up: step 4 of 4: told main-operator@hq the start is done; herdr is already running"
    )


@pytest.mark.parametrize(
    ("return_code", "reason"),
    [(1, "exited 1"), (0, "printed nothing")],
)
def test_config_read_failure_starts_herdr(
    fake_herdr, fake_rig, monkeypatch, capfd, return_code, reason
):
    reply, _ = fake_herdr
    reply((FIXTURES / "herdr-status-server-not-running.json").read_text())
    _, calls, execs = fake_rig
    monkeypatch.setenv("FAKE_OPERATOR", "")
    monkeypatch.setenv("FAKE_CONFIG_RC", str(return_code))
    assert rigs_up.main(ARGS) == 0
    assert not any(call["args"][:2] == ["queue", "create"] for call in calls())
    assert execs == [["herdr"]]
    out, err = capfd.readouterr()
    assert err == ""
    assert out.splitlines()[-1] == (
        f"rigs-up: step 4 of 4: couldn't tell Operator (rig config get agents.operator_session {reason}); starting herdr anyway"
    )


def test_config_read_failure_leaves_running_herdr(
    fake_herdr, fake_rig, monkeypatch, capfd
):
    _, calls, execs = fake_rig
    monkeypatch.setenv("FAKE_OPERATOR", "")
    monkeypatch.setenv("FAKE_CONFIG_RC", "1")
    assert rigs_up.main(ARGS) == 0
    assert not any(call["args"][:2] == ["queue", "create"] for call in calls())
    assert execs == []
    out, err = capfd.readouterr()
    assert err == ""
    assert out.splitlines()[-1] == (
        "rigs-up: step 4 of 4: couldn't tell Operator (rig config get agents.operator_session exited 1); herdr is already running"
    )


def test_never_started_with_none_stopped(fake_rig, capsys):
    set_responses, _, _ = fake_rig
    up = changed(
        {STOPPED},
        intentionallyStopped=False,
        sessionStatus="running",
        startupStatus="ready",
    )
    set_responses(up + [NEVER])
    assert rigs_up.main(ARGS) == 0
    lines, err = printed(capsys)
    assert (
        "rigs-up: step 3 of 4: 18 seats running, none stopped on purpose, "
        "1 recorded and never started (never.owner@oq-rigsup-fields)"
    ) in lines
    assert err == ""


def test_never_started_kernel_seat(fake_rig, capsys):
    set_responses, calls, _ = fake_rig
    set_responses(ALL_UP + [dict(NEVER, rigName="kernel")])
    assert rigs_up.main(ARGS) == 0
    assert not any(
        call["args"][:2] in (["start", "--last"], ["up", "kernel"]) for call in calls()
    )
    lines, err = printed(capsys)
    assert (
        "rigs-up: step 3 of 4: 17 seats running, 1 stopped on purpose "
        "(advisor-lead@kernel), 1 recorded and never started (never.owner@kernel)"
    ) in lines
    assert err == ""


def test_never_started_marked_stopped(fake_rig, capsys):
    set_responses, _, _ = fake_rig
    set_responses(ALL_UP + [dict(NEVER, intentionallyStopped=True)])
    assert rigs_up.main(ARGS) == 0
    lines, err = printed(capsys)
    assert STEP3N in lines
    assert err == ""


def test_two_never_started_seats_are_sorted_and_joined(fake_rig, capsys):
    set_responses, _, _ = fake_rig
    set_responses(ALL_UP + [NEVER, dict(NEVER, logicalId="another.owner")])
    assert rigs_up.main(ARGS) == 0
    lines, err = printed(capsys)
    assert (
        "rigs-up: step 3 of 4: 17 seats running, 1 stopped on purpose "
        "(advisor-lead@kernel), 2 recorded and never started "
        "(another.owner@oq-rigsup-fields, never.owner@oq-rigsup-fields)"
    ) in lines
    assert err == ""


def test_queue_message_time_is_utc(fake_rig, monkeypatch):
    import re
    import time
    from datetime import datetime, timezone

    _, calls, _ = fake_rig
    with monkeypatch.context() as zone:
        zone.setenv("TZ", "America/Chicago")
        time.tzset()
        before = datetime.now(timezone.utc).replace(microsecond=0)
        assert rigs_up.main(ARGS) == 0
        after = datetime.now(timezone.utc)
    time.tzset()
    body = calls()[-1]["args"][-1]
    stamp = re.match(r"rigs-up finished at (\S+Z):", body).group(1)
    made = datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    assert before <= made <= after


def test_help_lines_name_their_options(fake_rig, capsys):
    with pytest.raises(SystemExit):
        rigs_up.main(["--help"])
    output = " ".join(capsys.readouterr().out.split())
    assert (
        "--wait-seconds WAIT_SECONDS how long to wait for every seat, in seconds (default: 600)"
        in output
    )
    assert (
        "--poll-seconds POLL_SECONDS how often to check the seats, in seconds (default: 5)"
        in output
    )
