# Working in this repository

Read [ARCHITECTURE.md](ARCHITECTURE.md) first. It says what each piece is responsible for and what
each piece must not do.

- **Team files** (`rigs/*.yaml`, `agents/`) are OpenRig specs. After any change, run
  `rig spec validate <file>` on every team file you touched. A change reaches a running seat only
  at its next launch or restore, so say in the pull request which seats need one.
- **Code** follows Mark's build loop: one item per handoff, tests written first from the handoff's
  test cases, and every change through a pull request that Mark merges. Never push to `main`.
- **Never** put a secret in a team file, and never give a seat `HERDR_PANE_ID` or
  `HERDR_WORKSPACE_ID`.
