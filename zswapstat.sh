#!/usr/bin/env bash

# zswapstat - inspect zswap statistics and parameters
# Requires root (reads debugfs and /proc/meminfo).

set -euo pipefail

# --- configuration ----------------------------------------------------------
ZSWAP_DEBUG="/sys/kernel/debug/zswap"
ZSWAP_PARAMS="/sys/module/zswap/parameters"
PAGE_SIZE=$(getconf PAGE_SIZE)
BAR_WIDTH=30

# --- colors -----------------------------------------------------------------
# Detect whether stdout supports color. Honors NO_COLOR; only colors when the
# output is a TTY with at least 8 colors available. All vars are empty when off.
setup_colors() {
  if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    USE_COLOR=0
  elif command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null)" -ge 8 ]; then
    USE_COLOR=1
  else
    USE_COLOR=0
  fi

  if [ "$USE_COLOR" -eq 1 ]; then
    C_LABEL=$'\033[1;34m'   # field labels (blue)
    C_FILL=$'\033[1;32m'    # filled progress bar (green)
    C_EMPTY=$'\033[90m'     # empty progress bar (dim gray)
    C_VALUE=$'\033[1;33m'   # highlighted values (yellow)
    C_PERCENT=$'\033[1;32m' # accent values (yellow)
    C_RESET=$'\033[0m'
  else
    C_LABEL=""
    C_FILL=""
    C_EMPTY=""
    C_VALUE=""
    C_PERCENT=""
    C_RESET=""
  fi
}

# --- helpers ----------------------------------------------------------------
# read a single sysfs/debugfs value, fall back to 0 if missing/unreadable
read_val() {
  local path="$1"
  if [ -f "$path" ]; then
    cat "$path" 2>/dev/null || echo "Can't read value"
  else
    echo "No value"
  fi
}

# read a value from /proc/meminfo by key (returns bytes)
meminfo_bytes() {
  local key="$1:"
  local kb
  kb=$(awk -v k="$key" '$1==k {print $2; exit}' /proc/meminfo)
  echo $((${kb:-0} * 1024))
}

# human readable byte formatting (KiB/MiB/GiB)
format_bytes() {
  local bytes=$1
  if [ "$bytes" -ge 1073741824 ]; then
    echo "$(echo "scale=2; $bytes / 1073741824" | bc) GiB"
  elif [ "$bytes" -ge 1048576 ]; then
    echo "$(echo "scale=2; $bytes / 1048576" | bc) MiB"
  elif [ "$bytes" -ge 1024 ]; then
    echo "$(echo "scale=2; $bytes / 1024" | bc) KiB"
  else
    echo "$bytes B"
  fi
}

# build a 30-cell progress bar for a 0-100 percentage
prog_bar() {
  local pct=$1 bar=""
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if [ $((i * 100 / BAR_WIDTH)) -lt "$pct" ]; then
      bar+="${C_FILL}█"
    else
      bar+="${C_EMPTY}░"
    fi
  done
  printf '%s%s' "$bar" "$C_RESET"
}

# 0-100 percentage, clamped, guarding divide-by-zero
pct_of() {
  local used=$1 total=$2
  if [ "$total" -le 0 ]; then
    echo 0
  else
    echo $((used * 100 / total))
  fi
}

# --- data collection --------------------------------------------------------
collect() {
  # zswap statistics (debugfs)
  stored_pages=$(read_val "$ZSWAP_DEBUG/stored_pages")
  pool_total_size=$(read_val "$ZSWAP_DEBUG/pool_total_size")
  incompressible=$(read_val "$ZSWAP_DEBUG/stored_incompressible_pages")
  written_back=$(read_val "$ZSWAP_DEBUG/written_back_pages")
  decompress_fail=$(read_val "$ZSWAP_DEBUG/decompress_fail")
  reject_compress_poor=$(read_val "$ZSWAP_DEBUG/reject_compress_poor")
  reject_compress_fail=$(read_val "$ZSWAP_DEBUG/reject_compress_fail")
  reject_kmemcache_fail=$(read_val "$ZSWAP_DEBUG/reject_kmemcache_fail")
  reject_alloc_fail=$(read_val "$ZSWAP_DEBUG/reject_alloc_fail")
  reject_reclaim_fail=$(read_val "$ZSWAP_DEBUG/reject_reclaim_fail")
  pool_limit_hit=$(read_val "$ZSWAP_DEBUG/pool_limit_hit")

  # zswap parameters (module)
  enabled=$(read_val "$ZSWAP_PARAMS/enabled")
  shrinker_enabled=$(read_val "$ZSWAP_PARAMS/shrinker_enabled")
  max_pool_percent=$(read_val "$ZSWAP_PARAMS/max_pool_percent")
  compressor=$(read_val "$ZSWAP_PARAMS/compressor")
  accept_threshold_percent=$(read_val "$ZSWAP_PARAMS/accept_threshold_percent")

  # memory + swap (procfs)
  mem_total=$(meminfo_bytes MemTotal)
  mem_avail=$(meminfo_bytes MemAvailable)
  mem_used=$((mem_total - mem_avail))
  swap_total=$(meminfo_bytes SwapTotal)
  swap_free=$(meminfo_bytes SwapFree)
  swap_used=$((swap_total - swap_free))

  # derived zswap metrics
  orig_size=$((stored_pages * PAGE_SIZE))
  if [ "$pool_total_size" -gt 0 ]; then
    saved_size=$((orig_size > pool_total_size ? orig_size - pool_total_size : 0))
    ratio=$(echo "scale=2; $orig_size / $pool_total_size" | bc)
    saved_pct=$(echo "scale=1; ($saved_size * 100) / $orig_size" | bc)
  else
    saved_size=0
    ratio="0.00"
    saved_pct="0.0"
  fi

  # zswap pool capacity = RAM * max_pool_percent
  zswap_cap=$((mem_total * max_pool_percent / 100))
}

# print "KEY : VALUE" with the key colored; optional 3rd arg colors the value
print_kv() {
  local key="$1" value="$2"
  local ckey cval
  ckey=$(printf "$C_LABEL%-12s$C_RESET" "$key")
  cval=$(printf "$C_VALUE%s$C_RESET" "$value")
  echo "$ckey : $cval"
}

print_long_kv() {
  local key="$1" value="$2"
  local ckey cval
  ckey=$(printf "$C_LABEL%-28s$C_RESET" "$key")
  cval=$(printf "$C_VALUE%s$C_RESET" "$value")
  echo "  $ckey : $cval"
}

# print "KEY : [BAR] PCT% REST" with the key colored
print_kv_bar() {
  local key="$1" value1="$2" value2="$3" progress_bar value_pct
  value_pct="$(pct_of "$value1" "$value2")"
  progress_bar="[$(prog_bar "$value_pct")]"
  value1="$(format_bytes "$value1")"
  value2="$(format_bytes "$value2")"
  printf "$C_LABEL%-12s$C_RESET : %s $C_PERCENT%s $C_VALUE%10s/%10s$C_RESET\n" "$key" "$progress_bar" "${value_pct}%" "$value1" "$value2"
}

# --- output -----------------------------------------------------------------
print_minimal() {
  print_kv_bar "RAM Usage" "$mem_used" "$mem_total"
  print_kv_bar "Swap Usage" "$swap_used" "$swap_total"
  print_kv_bar "Zswap Usage" "$pool_total_size" "$zswap_cap"
  print_kv "Zswap Data" "$(format_bytes "$orig_size")"
  print_kv "Compr Ratio" "${ratio}x"
}

print_full() {
  print_minimal
  echo
  echo "${C_LABEL}Statistics:${C_RESET}"
  print_long_kv "stored_pages" "$stored_pages"
  print_long_kv "pool_total_size" "$(format_bytes "$pool_total_size")"
  print_long_kv "stored_incompressible_pages" "$incompressible"
  print_long_kv "written_back_pages" "$written_back"
  print_long_kv "decompress_fail" "$decompress_fail"
  print_long_kv "reject_compress_poor" "$reject_compress_poor"
  print_long_kv "reject_compress_fail" "$reject_compress_fail"
  print_long_kv "reject_kmemcache_fail" "$reject_kmemcache_fail"
  print_long_kv "reject_alloc_fail" "$reject_alloc_fail"
  print_long_kv "reject_reclaim_fail" "$reject_reclaim_fail"
  print_long_kv "pool_limit_hit" "$pool_limit_hit"
  print_long_kv "memory_saved" "$(format_bytes "$saved_size") ($saved_pct%)"
  echo
  echo "${C_LABEL}Parameters:${C_RESET}"
  print_long_kv "enabled" "$enabled"
  print_long_kv "shrinker_enabled" "$shrinker_enabled"
  print_long_kv "max_pool_percent" "$max_pool_percent"
  print_long_kv "compressor" "$compressor"
  print_long_kv "accept_threshold_percent" "$accept_threshold_percent"
}

print_help() {
  cat <<'EOF'
zswapstat - inspect zswap statistics and parameters

Usage:
  zswapstat [COMMAND] [OPTIONS…]

Commands:
  status                     Show compact status (RAM/Swap/Zswap usage bars) [default]
  status --all               Show all zswap statistics and parameters
  dashboard, -d              Live dashboard (btop-like) [not implemented yet]

Options:
  --all, -a                  Show all statistics and parameters
  --help, -h                 Show this help
EOF
}

print_dashboard() {
  # ponytail: reserved for a future live btop-like dashboard with line charts.
  # Planned: refresh loop showing RAM/Swap/Zswap with ASCII line graphs.
  echo "Dashboard not implemented yet."
  echo "(reserved for future btop-like live view with line charts)"
}

# --- argument parsing -------------------------------------------------------
MODE="minimal"
case "${1:-}" in
"" | status)
  MODE="minimal"
  if [ "${2:-}" = "--all" ] || [ "${2:-}" = "-a" ]; then MODE="full"; fi
  ;;
dashboard | -d)
  MODE="dashboard"
  ;;
--all | -a)
  MODE="full"
  ;;
--help | -h)
  print_help
  exit 0
  ;;
*)
  echo "Error: unknown argument '$1'." >&2
  print_help
  exit 1
  ;;
esac

# --- self-elevate -----------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

# --- preflight --------------------------------------------------------------

if [ ! -d "$ZSWAP_DEBUG" ]; then
  echo "Error: $ZSWAP_DEBUG not found. Mount debugfs and enable zswap." >&2
  exit 1
fi

collect
setup_colors

case "$MODE" in
minimal) print_minimal ;;
full) print_full ;;
dashboard) print_dashboard ;;
esac
