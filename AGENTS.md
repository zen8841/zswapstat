# AGENTS.md

Single-file bash tool: `zswapstat.sh`. Inspects zswap statistics, RAM, and swap.

## Run it
- Requires root (reads `/sys/kernel/debug/zswap` and `/proc/meminfo`).
- `bc` must be installed (used for float math: compression ratio, %).
- If `chmod` is blocked by policy, run with `bash zswapstat.sh ...` instead of `./zswapstat.sh`.

## Commands
- `zswapstat.sh` or `zswapstat.sh status` → compact view: RAM/Swap/Zswap usage bars + Zswap orig size + comp ratio.
- `zswapstat.sh status --all` or `zswapstat.sh --all` / `-a` → above plus all debugfs stats and module params.
- `zswapstat.sh dashboard` / `-d` → live btop-like view. **Not implemented** (reserved stub; future ASCII line charts).
- `zswapstat.sh --help` / `-h` → usage.

## Conventions / gotchas
- Comments and user-facing messages are **English only** (project requirement).
- `/proc/meminfo` field 1 includes the trailing colon (`MemTotal:`), not `MemTotal` — match with the colon.
- Zswap "capacity" = RAM total × `max_pool_percent` (from `/sys/module/zswap/parameters/max_pool_percent`); Zswap usage % is `pool_total_size / capacity`.
- Page size read via `getconf PAGE_SIZE` (not hardcoded).
- Colors auto-detect TTY + `tput colors` ≥ 8; honors `NO_COLOR` env var.
- No build system, tests, or linter in this repo. Verify with `bash -n zswapstat.sh` for syntax.
- `ponytail:` comment in `print_dashboard()` marks the reserved stub for future implementation.