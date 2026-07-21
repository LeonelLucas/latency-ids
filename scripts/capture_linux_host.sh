#!/usr/bin/env sh
set -eu

OUTPUT_PATH="${1:-host_metadata.txt}"

{
  date --iso-8601=seconds 2>/dev/null || date
  uname -a
  command -v lscpu >/dev/null 2>&1 && lscpu
  command -v nproc >/dev/null 2>&1 && nproc
  if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    printf 'scaling_governor='
    head -n 1 /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
  fi
  if [ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
    printf 'intel_pstate_no_turbo='
    head -n 1 /sys/devices/system/cpu/intel_pstate/no_turbo
  fi
  if command -v docker >/dev/null 2>&1; then
    docker version
  fi
} > "$OUTPUT_PATH"

printf 'Wrote %s\n' "$OUTPUT_PATH"

