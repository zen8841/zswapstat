# zswapstat

Inspect zswap statistics, RAM, and swap usage from the command line.

## Features

- **Compact status view** — RAM, swap, and zswap usage bars with compression ratio
- **Full statistics** — All zswap debugfs counters and module parameters
- **Colorized output** — Auto-detects TTY, honors `NO_COLOR`, requires 8+ colors
- **Human-readable** — Bytes formatted as KiB/MiB/GiB
- **Single file** — No dependencies beyond `bash` and `bc`

## Requirements

- **Root privileges** (reads `/sys/kernel/debug/zswap` and `/proc/meminfo`; script auto-elevates via `sudo`)
- `bc` installed (for floating-point math: compression ratio, percentages)
- `debugfs` mounted at `/sys/kernel/debug`
- zswap enabled in kernel (`CONFIG_ZSWAP=y`)

## Installation

```bash
# Install script
sudo cp zswapstat.sh /usr/local/bin/zswapstat
sudo chmod +x /usr/local/bin/zswapstat

# Allow running without password prompt
sudo install -Dm440 zswapstat-sudoers /etc/sudoers.d/zswapstat
```

After installation, run `zswapstat` directly — it auto-elevates to root.

## Usage

```bash
# Compact status (default)
zswapstat
zswapstat status

# Full statistics + parameters
zswapstat status --all
zswapstat --all
zswapstat -a

# Help
zswapstat --help
zswapstat -h

# Dashboard (not yet implemented)
zswapstat dashboard
zswapstat -d
```

## Example Output

```
RAM Usage   : [████████████████░░░░░░░░░░] 53%   8.00 GiB/15.00 GiB
Swap Usage  : [████░░░░░░░░░░░░░░░░░░░░] 12%   512.00 MiB/4.00 GiB
Zswap Usage : [████████░░░░░░░░░░░░░░░░] 27%   1.00 GiB/4.00 GiB
Zswap Data  : 2.50 GiB
Compr Ratio : 2.50x
```

With `--all` you also get:

```
Statistics:
  stored_pages                : 123456
  pool_total_size             : 1.00 GiB
  stored_incompressible_pages : 12
  written_back_pages          : 45
  decompress_fail             : 0
  reject_compress_poor        : 3
  reject_compress_fail        : 0
  reject_kmemcache_fail       : 0
  reject_alloc_fail           : 0
  reject_reclaim_fail         : 0
  pool_limit_hit              : 0
  memory_saved                : 1.50 GiB (60.0%)

Parameters:
  enabled                     : Y
  shrinker_enabled            : Y
  max_pool_percent            : 20
  compressor                  : lzo-rle
  accept_threshold_percent    : 90
```

## Key Metrics Explained

| Metric | Meaning |
|--------|---------|
| **Zswap Usage** | `pool_total_size / (RAM × max_pool_percent)` — how much of the zswap pool is used |
| **Zswap Data** | Original (uncompressed) size of stored pages (`stored_pages × PAGE_SIZE`) |
| **Compr Ratio** | `original_size / pool_total_size` — higher = better compression |
| **memory_saved** | `original_size - pool_total_size` — RAM saved by compression |

## License

AGPL-3.0 — see [LICENSE](LICENSE) for details.