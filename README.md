# workflow-engine

The OpenRig team files for Mark's agent teams, and the code that lays the teams out in herdr.

- `rigs/` holds one RigSpec per team: `hq`, `platform`, `tooling`, `operations` and
  `workflow-engine`.
- `agents/` holds the two seat kinds, the lead and a project owner.

Bring a stopped team back with `rig up <team> --existing`, and check a team file with
`rig spec validate rigs/<team>.yaml`. How the pieces fit is in [ARCHITECTURE.md](ARCHITECTURE.md).
