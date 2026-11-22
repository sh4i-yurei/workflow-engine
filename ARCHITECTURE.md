# Architecture

This repository holds the files that define Mark's OpenRig teams, the code that makes those
teams usable on his screen, and the tools that keep them running. OpenRig runs each team as a rig
of Claude Code seats in tmux; herdr is the terminal Mark watches them in. The design decisions
behind it live in the vault, in the OpenRig team project note (decisions 5 to 15) and the Workflow
upkeep project note (decision 80).

## The shape

Three kinds of thing live here.

The **team files** are data. Each file in `rigs/` is an OpenRig RigSpec for one team: its pods,
one per project, and each pod's seats, with the seat's role, working folder, permission policy,
denied tools and declared herdr name (`env: {AGENT_NAME: <name>}`). The files in `agents/` define
the two kinds of seat, the lead (`operator`) and a project owner (`owner`), and the role text each
one starts with. OpenRig reads these files when a team is brought up; nothing in this repository
runs them.

The **team-view step** is code, still to be built (OpenRig team decision 14). It makes each team's
herdr space look the way the team files say it should: one workspace per team, the owners' tiles
in tabs of at most four with readable names, and every agent tile named with its declared name.
It reads the team files and herdr's current state, works out what is missing, and asks herdr and
OpenRig to make the changes. It runs after every power-on and whenever a team's view is needed,
and running it twice changes nothing the second time.

The **operational tools** keep a running team safe. The first is the database backup (OpenRig
team decision 15). OpenRig's queue is the only record of open work between agents (Workflow
engine decision 31), and it lives in one SQLite file, `~/.openrig/openrig.sqlite`. Every hour a
systemd user timer on the host runs `tools/openrig_backup.py`, which copies that file with
SQLite's online backup while the daemon keeps writing, checks the copy, compresses it, and keeps
48 hours of copies in `~/.openrig/backups/db/`. It runs on the host, not in a container, because
nothing has to be installed for it there, and because a container would have to relabel the live
OpenRig folder for SELinux. A copy of the script and its units is installed from a merged
commit, so the timer never runs whatever branch a checkout happens to be on.

```text
~/.openrig/openrig.sqlite ──online backup──▶ .partial copy ──integrity check──▶ xz ──rename──▶ ~/.openrig/backups/db/openrig-<UTC>.sqlite.xz
                                                                                              └──after a good copy: remove copies over 48 h old
```

```text
rigs/*.yaml ──read──▶ team reader ──┐
                                    ├──▶ planner (pure) ──actions──▶ executor ──▶ herdr CLI, rig CLI
herdr CLI ───read──▶ herdr reader ──┘
```

## The pieces

| Piece | Responsibility | Interface | Depends on | How it fails | Must not |
|---|---|---|---|---|---|
| `rigs/*.yaml` | Define each team, its seats and each seat's herdr name | OpenRig RigSpec 0.2, checked with `rig spec validate` | `agents/` | `rig spec validate` names the bad field | hold secrets; name a seat outside herdr's rule `[a-z][a-z0-9_-]{0,31}` |
| `agents/` | Define the lead and the owner seat kinds and their role text | OpenRig agent specs | OpenRig's shared agent spec | `rig up` refuses a missing or invalid spec | carry one project's details; those go in the team file's startup file |
| Team reader (planned) | Turn the team files into a list of teams, each with its seats' sessions, labels and names | a function returning plain data | PyYAML | raises on a file that isn't valid YAML or lacks a field it needs | run a command, or read anything but `rigs/` |
| herdr reader (planned) | Take a snapshot of herdr: workspaces, tabs, panes, agent names, and which seat each tile attaches to | a function returning plain data | the `herdr` CLI's JSON output | raises when herdr can't be reached or answers in a shape it doesn't know | change anything in herdr |
| Planner (planned) | Compare the teams with the snapshot and list the actions that close the gap | a pure function, teams plus snapshot in, actions out | nothing | it can't fail at run time; a team it can't place is reported as an action that needs a person | call a command, read a file, or plan any change to an owner's `<agent name> jobs` tab |
| Executor (planned) | Carry out the actions in order and report each result | a function taking the actions | the `herdr` and `rig` CLIs | stops at the first failed action, reports it and exits nonzero | close a pane, or carry out an action the planner didn't list |
| Command (planned) | Run the step for every team or one team, with a dry run that prints the plan | `team-view [--team <rig>] [--dry-run]` | all of the above | exit 0 when done or nothing to do, 1 when an action failed, 2 on bad input | prompt for input |
| `tools/openrig_backup.py` | Copy OpenRig's database, check the copy, compress it, keep it for 48 hours, and remove older copies after a good one | `openrig_backup.py [--db PATH] [--dest DIR] [--keep-hours N]`, run by `/usr/bin/python3` | Python's standard library only (`sqlite3`, `lzma`) | exit 1 with one line on standard error when the database can't be read or the copy fails its check, after deleting its own unfinished files; nothing is pruned after a failure; exit 2 on bad arguments | write to the live database, open it any way but read-only, or delete a file in the copies folder whose name isn't one of its own copies or unfinished files |
| `systemd/openrig-backup.service`, `.timer` | Run the backup hourly on the host, catching up on a missed hour | systemd user units, installed as copies under `~/.config/systemd/user/` | systemd's user manager, `/usr/bin/python3` | a failed run shows as a failed unit in `systemctl --user status` | run anything but the installed copy of the script |

The planner is pure so that every rule about what a team's space should look like can be tested
without herdr or OpenRig running, and so its mutants can be killed by ordinary tests.

## Rules every piece follows

- **The CLIs are the authority.** The step changes herdr only through the `herdr` CLI and OpenRig
  only through the `rig` CLI. It never writes herdr's `session.json`, tmux's environment or
  OpenRig's database.
- **A tile is mapped to its seat from herdr itself.** `herdr pane process-info --pane <id>` shows
  the tile's attach script, whose arguments carry the seat's session name after `openrig-tile`.
- **A team that already has tiles is never reopened.** Once a team's tab has been renamed,
  `rig terminal open <rig>` no longer recognises the view and opens a duplicate workspace. The step
  opens a view only for a team with no tiles at all.
- **The seat's name comes from its team file.** The step reads `AGENT_NAME` from the seat's tmux
  session when it is set, and from the team file otherwise, because a running seat only gets a
  newly declared name at its next launch.
- **Job tabs belong to their owners.** The step never creates, changes or closes a tab named
  `<agent name> jobs` or `<agent name> jobs N` (Workflow upkeep decision 80).
- **Seats never get `HERDR_PANE_ID` or `HERDR_WORKSPACE_ID`.** With them, claude-config's
  herdr-name hook would rename every seat after its workspace.
- **Pinned tools.** Every dependency and CI action is pinned to an exact version or commit.
- **Operational tools use only the host's standard library.** The host has no Node, no Go and no
  extra Python packages, and a backup must run when other things are broken, so a tool here
  imports nothing outside Python's standard library.
- **Tests run as `python -m pytest` from the repository root.** No `pythonpath` setting and no
  `sys.path` edits in a conftest, because mutmut swaps in its own copy of `tools/` and either one
  makes every mutant look untested.
