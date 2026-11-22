# workflow-engine

The OpenRig team files, the code that lays the teams out in herdr, and two tools that keep the teams running: a database backup and rigs-up.

- `rigs/` holds one RigSpec per team: `hq`, `platform`, `tooling`, `operations` and
  `workflow-engine`.
- `agents/` holds the two seat kinds, the lead and a project owner.

Bring a stopped team back with `rig up <team> --existing`, and check a team file with
`rig spec validate rigs/<team>.yaml`. How the pieces fit is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Database backup

The systemd user timer runs an online backup of OpenRig's database every hour. It checks and compresses each copy, stores it in `~/.openrig/backups/db/`, and keeps copies for 48 hours.

After the change has been merged, install a copy from the merged checkout on the host:

```bash
install -D -m 0644 tools/openrig_backup.py ~/.local/lib/openrig-backup/openrig_backup.py
install -D -m 0644 -t ~/.config/systemd/user/ systemd/openrig-backup.service systemd/openrig-backup.timer
systemctl --user daemon-reload
systemctl --user enable --now openrig-backup.timer
```

To restore a chosen copy, stop the daemon with `rig daemon stop`. Decompress the copy over the database with `xz -dc ~/.openrig/backups/db/<copy> > ~/.openrig/openrig.sqlite`. Remove `~/.openrig/openrig.sqlite-wal` and `~/.openrig/openrig.sqlite-shm`. Replay any queue erasure made after the copy's time as OpenRig's queue-erasure guide says. Start OpenRig the usual way with `rig start` from a fresh terminal (OpenRig team decision 10). Afterwards, check that the kernel's advisor seat is still stopped (decision 11).

## Starting everything after a reboot

Type `rigs-up` in a Ghostty window on the host or in dev. It brings every OpenRig team back and then opens herdr. If herdr is already running, rigs-up leaves it as it is. Unlocking the vault with `vu` is a separate step. The vault reference note `openrig-restart` has the manual fallback.

After the change has been merged, install a copy from the merged checkout:

```bash
install -D -m 0755 tools/rigs_up.py ~/.local/bin/rigs-up
```
