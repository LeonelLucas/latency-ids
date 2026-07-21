#!/usr/bin/env bash
# Self-contained Linux runner for the latency-aware IDS artifact.
# Default: download/verify CNS2022 CICIDS2017, build a pinned Docker image,
# run the definitive experiment on one CPU, validate it, and create one
# compact .tar.gz to send back for analysis.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="2026-07-20.1"
readonly DATASET_URL="https://intrusion-detection.distrinet-research.be/CNS2022/Datasets/CICIDS2017_improved.zip"
readonly DATASET_ARCHIVE_SHA256="97fdb91d339e2d8cf5627f981b831e5e7e400b981c58181c451a38fd03c48883"
readonly EXPECTED_MONDAY_SHA256="51fe5dc962626efb4ae70dce0303072fb780da0932822b651202ee9c2fbc1aff"
readonly EXPECTED_TUESDAY_SHA256="e2a0a5b631dfc6b455cc9f9a88b944110637d70a7f74171473925f76f38b6b0c"
readonly EXPECTED_WEDNESDAY_SHA256="bf46c5f3c792e8817381f724511229569606918eaf07ac986d7a2592b6341bc2"
readonly EXPECTED_THURSDAY_SHA256="78a4d11eaf473d099e30e71ddb01e0f38218e844c0a9cdd36602145d674af482"
readonly EXPECTED_FRIDAY_SHA256="ebd499e6f23bd59f9cb81bec28178491b02b925fa5640a24215c9437d79482d0"

say() { printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

MONITOR_PID=""

stop_monitor() {
  if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" >/dev/null 2>&1; then
    kill "$MONITOR_PID" >/dev/null 2>&1 || true
    wait "$MONITOR_PID" >/dev/null 2>&1 || true
  fi
  MONITOR_PID=""
}

on_error() {
  local line="$1" status="$2"
  printf '\nERROR at line %s (status %s). Partial files were preserved.\n' "$line" "$status" >&2
}
trap 'on_error "$LINENO" "$?"' ERR
trap 'stop_monitor' EXIT
trap 'printf "\nExecution interrupted; partial files were preserved.\n" >&2; exit 130' INT TERM

usage() {
  cat <<'USAGE'
Usage:
  bash run_definitive_linux.sh [CSV_DIRECTORY]

Without an argument, the script searches for the CSV files in the current
directory. If they are absent, it downloads and verifies CNS2022 CICIDS2017.

Optional variables:
  LADC_DATA_DIR=/path/to/csvs        alternative to the positional argument
  LADC_CPU=3                         dedicated logical CPU (default: last online)
  LADC_OUTPUT_DIR=/path/to/run       complete run directory
  LADC_ARCHIVE=/path/to/file.tar.gz final compact package
  LADC_PROFILE=definitive|smoke      default: definitive
  LADC_STRICT_CONTROLS=1|0           require performance governor when definitive
  LADC_MAX_LOAD1=0.50                maximum load before benchmark
  LADC_COOLDOWN_SECONDS=30           minimum pause after training
  LADC_QUIET_WAIT_SECONDS=300        maximum wait for an idle host

Normal definitive example:
  bash run_definitive_linux.sh

Short diagnostic test:
  LADC_PROFILE=smoke bash run_definitive_linux.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ $# -le 1 ]] || { usage >&2; die "At most one data directory is accepted."; }
[[ "$(uname -s)" == "Linux" ]] || die "This runner must execute on Linux (uname: $(uname -s))."
(( BASH_VERSINFO[0] >= 4 )) || die "Bash 4 or newer is required."

PROFILE="${LADC_PROFILE:-definitive}"
[[ "$PROFILE" == "definitive" || "$PROFILE" == "smoke" ]] || die "LADC_PROFILE must be definitive or smoke."
STRICT_CONTROLS="${LADC_STRICT_CONTROLS:-1}"
MAX_LOAD1="${LADC_MAX_LOAD1:-0.50}"
COOLDOWN_SECONDS="${LADC_COOLDOWN_SECONDS:-30}"
QUIET_WAIT_SECONDS="${LADC_QUIET_WAIT_SECONDS:-300}"
MONITOR_INTERVAL_SECONDS="${LADC_MONITOR_INTERVAL_SECONDS:-2}"
[[ "$STRICT_CONTROLS" == "0" || "$STRICT_CONTROLS" == "1" ]] || die "LADC_STRICT_CONTROLS must be 0 or 1."
[[ "$MAX_LOAD1" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "LADC_MAX_LOAD1 must be numeric."
[[ "$COOLDOWN_SECONDS" =~ ^[0-9]+$ ]] || die "LADC_COOLDOWN_SECONDS must be an integer."
[[ "$QUIET_WAIT_SECONDS" =~ ^[0-9]+$ ]] || die "LADC_QUIET_WAIT_SECONDS must be an integer."
[[ "$MONITOR_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "LADC_MONITOR_INTERVAL_SECONDS must be a positive integer."

SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
START_DIR="$(pwd -P)"
RUN_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_ROOT="${LADC_OUTPUT_DIR:-$START_DIR/ladc-run-$PROFILE-$RUN_STAMP}"
ARCHIVE_PATH="${LADC_ARCHIVE:-$START_DIR/ladc-results-$PROFILE-$RUN_STAMP.tar.gz}"
DATA_INPUT="${1:-${LADC_DATA_DIR:-}}"
IMAGE_TAG="ladc-latency-artifact:$RUN_STAMP"

[[ ! -e "$RUN_ROOT" ]] || die "The run directory already exists: $RUN_ROOT"
[[ ! -e "$ARCHIVE_PATH" ]] || die "The final package already exists: $ARCHIVE_PATH"
mkdir -p "$RUN_ROOT" "$(dirname "$ARCHIVE_PATH")"
RUN_ROOT="$(cd "$RUN_ROOT" && pwd -P)"
ARCHIVE_PATH="$(cd "$(dirname "$ARCHIVE_PATH")" && pwd -P)/$(basename "$ARCHIVE_PATH")"
LOG_DIR="$RUN_ROOT/logs"
HOST_DIR="$RUN_ROOT/host"
SNAPSHOT_DIR="$RUN_ROOT/artifact_snapshot"
RESULTS_ROOT="$RUN_ROOT/results"
mkdir -p "$LOG_DIR" "$HOST_DIR" "$SNAPSHOT_DIR" "$RESULTS_ROOT"
printf '%s\n' "$SCRIPT_VERSION" > "$RUN_ROOT/runner_version.txt"

SUDO=()
if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 && SUDO=(sudo)
fi

install_host_dependencies() {
  local missing=0 tool
  for tool in curl unzip tar gzip base64 sha256sum docker; do
    command -v "$tool" >/dev/null 2>&1 || missing=1
  done
  (( missing == 0 )) && return 0

  if (( EUID != 0 )) && (( ${#SUDO[@]} == 0 )); then
    die "Dependencies are missing and sudo is unavailable to install them."
  fi

  say "Installing host utilities and Docker"
  if command -v apt-get >/dev/null 2>&1; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip tar gzip coreutils docker.io
  elif command -v dnf >/dev/null 2>&1; then
    "${SUDO[@]}" dnf install -y ca-certificates curl unzip tar gzip coreutils docker
  elif command -v yum >/dev/null 2>&1; then
    "${SUDO[@]}" yum install -y ca-certificates curl unzip tar gzip coreutils docker
  elif command -v pacman >/dev/null 2>&1; then
    "${SUDO[@]}" pacman -Sy --needed --noconfirm ca-certificates curl unzip tar gzip coreutils docker
  else
    die "Unsupported package manager. Install curl, unzip, tar, gzip, coreutils, and Docker Engine."
  fi
}

DOCKER=()
configure_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker CLI was not installed."
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    "${SUDO[@]}" systemctl enable --now docker || "${SUDO[@]}" systemctl start docker || true
  elif command -v service >/dev/null 2>&1; then
    "${SUDO[@]}" service docker start || true
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif (( EUID == 0 )) && docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif (( ${#SUDO[@]} > 0 )) && "${SUDO[@]}" docker info >/dev/null 2>&1; then
    DOCKER=("${SUDO[@]}" docker)
  else
    die "Docker was found, but the daemon is unavailable. Check 'systemctl status docker'."
  fi
}

install_host_dependencies
configure_docker

for tool in curl unzip tar gzip base64 sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "Dependency still missing after installation: $tool"
done

available_kib="$(df -Pk "$START_DIR" | awk 'NR==2 {print $4}')"
memory_kib="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
(( available_kib >= 12 * 1024 * 1024 )) || warn "The execution filesystem has less than 12 GiB free."
(( memory_kib >= 8 * 1024 * 1024 )) || warn "The host has less than 8 GiB RAM; the definitive profile may fail."

detect_dataset_dir() {
  local candidate
  if [[ -n "$DATA_INPUT" ]]; then
    [[ -d "$DATA_INPUT" ]] || die "Data directory does not exist: $DATA_INPUT"
    DATA_DIR="$(cd "$DATA_INPUT" && pwd -P)"
    return
  fi

  for candidate in \
    "$START_DIR/CICIDS2017_improved_CNS2022" \
    "$START_DIR/CICIDS2017_improved" \
    "$START_DIR/ladc-data" \
    "$START_DIR"; do
    if [[ -f "$candidate/monday.csv" && -f "$candidate/friday.csv" ]]; then
      DATA_DIR="$(cd "$candidate" && pwd -P)"
      return
    fi
  done

  DATA_DIR="$START_DIR/ladc-data"
  mkdir -p "$DATA_DIR"
  DATA_DIR="$(cd "$DATA_DIR" && pwd -P)"
  local archive="$DATA_DIR/CICIDS2017_improved.zip"
  if [[ -f "$archive" ]] && printf '%s  %s\n' "$DATASET_ARCHIVE_SHA256" "$archive" | sha256sum --check --status; then
    say "Reusing the previously downloaded and verified ZIP"
  else
    say "Downloading CNS2022 CICIDS2017 (approximately 328 MiB)"
    curl --fail --location --retry 5 --retry-delay 5 --continue-at - \
      --output "$archive" "$DATASET_URL"
  fi
  printf '%s  %s\n' "$DATASET_ARCHIVE_SHA256" "$archive" | sha256sum --check --status \
    || die "Incorrect SHA-256 for the downloaded ZIP: $archive"
  say "Extracting the five CSV files (approximately 1.15 GiB)"
  unzip -n -q "$archive" -d "$DATA_DIR"
}

verify_dataset() {
  local failed=0 file expected actual
  while IFS=' ' read -r file expected; do
    if [[ ! -f "$DATA_DIR/$file" ]]; then
      printf 'MISSING  %s\n' "$DATA_DIR/$file" >&2
      failed=1
      continue
    fi
    actual="$(sha256sum "$DATA_DIR/$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      printf 'INVALID SHA  %s\n  expected=%s\n  observed=%s\n' "$file" "$expected" "$actual" >&2
      failed=1
    else
      printf '%s  %s\n' "$actual" "$file"
    fi
  done <<EOF
monday.csv $EXPECTED_MONDAY_SHA256
tuesday.csv $EXPECTED_TUESDAY_SHA256
wednesday.csv $EXPECTED_WEDNESDAY_SHA256
thursday.csv $EXPECTED_THURSDAY_SHA256
friday.csv $EXPECTED_FRIDAY_SHA256
EOF
  (( failed == 0 )) || die "The dataset does not match the expected CNS2022 CICIDS2017 release."
}

detect_dataset_dir
say "Verifying the five CSV files with SHA-256"
verify_dataset | tee "$LOG_DIR/dataset_sha256.txt"

ONLINE_CPUS="$(nproc)"
if command -v lscpu >/dev/null 2>&1; then
  DEFAULT_CPU="$(lscpu -p=CPU,ONLINE | awk -F, '$1 !~ /^#/ && $2 == "Y" {cpu=$1} END {print cpu}')"
else
  DEFAULT_CPU="$(( ONLINE_CPUS - 1 ))"
fi
CPU="${LADC_CPU:-$DEFAULT_CPU}"
[[ "$CPU" =~ ^[0-9]+$ ]] || die "LADC_CPU must be a non-negative integer."
[[ -d "/sys/devices/system/cpu/cpu$CPU" ]] || die "Logical CPU $CPU does not exist."
if [[ -r "/sys/devices/system/cpu/cpu$CPU/online" ]]; then
  [[ "$(<"/sys/devices/system/cpu/cpu$CPU/online")" == "1" ]] || die "Logical CPU $CPU is offline."
fi

GOVERNOR_FILE="/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor"
if [[ -r "$GOVERNOR_FILE" ]]; then
  GOVERNOR="$(<"$GOVERNOR_FILE")"
  if [[ "$GOVERNOR" != "performance" ]]; then
    if [[ "$PROFILE" == "definitive" && "$STRICT_CONTROLS" == "1" ]]; then
      die "CPU $CPU uses governor '$GOVERNOR'. Configure 'performance' before replication (for example: sudo cpupower frequency-set -g performance)."
    fi
    warn "CPU $CPU uses governor '$GOVERNOR'."
  fi
elif [[ "$PROFILE" == "definitive" && "$STRICT_CONTROLS" == "1" ]]; then
  die "Could not verify the governor for CPU $CPU: $GOVERNOR_FILE"
fi

capture_host() {
  local phase="$1"
  local destination="$HOST_DIR/host_${phase}.txt"
  (
    set +e
    printf 'runner_version=%s\nprofile=%s\nselected_cpu=%s\ndata_dir=%s\nrun_root=%s\nstrict_controls=%s\nmax_load1=%s\n' \
      "$SCRIPT_VERSION" "$PROFILE" "$CPU" "$DATA_DIR" "$RUN_ROOT" "$STRICT_CONTROLS" "$MAX_LOAD1"
    date --iso-8601=seconds
    uname -a
    printf '\n/proc/cmdline\n'; cat /proc/cmdline
    printf '\nlscpu\n'; lscpu
    printf '\nnproc\n'; nproc; nproc --all
    printf '\n/proc/loadavg\n'; cat /proc/loadavg
    printf '\nfree\n'; free -h
    printf '\ndf\n'; df -h "$START_DIR" "$DATA_DIR" "$RUN_ROOT"
    printf '\nclocksource\n'; cat /sys/devices/system/clocksource/clocksource0/current_clocksource
    printf '\nselected_cpu_sysfs\n'
    for path in \
      "/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor" \
      "/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq" \
      "/sys/devices/system/cpu/cpu$CPU/cpufreq/cpuinfo_max_freq" \
      "/sys/devices/system/cpu/intel_pstate/no_turbo" \
      "/sys/devices/system/cpu/cpufreq/boost"; do
      [[ -r "$path" ]] && printf '%s=%s\n' "$path" "$(<"$path")"
    done
    printf '\nuptime\n'; uptime
    printf '\ntop_cpu_processes\n'; ps -eo pid,psr,pcpu,pmem,comm --sort=-pcpu | head -n 25
    if command -v sensors >/dev/null 2>&1; then printf '\nsensors\n'; sensors; fi
    printf '\ndocker_version\n'; "${DOCKER[@]}" version
    printf '\ndocker_info\n'; "${DOCKER[@]}" info
  ) > "$destination" 2>&1
}

wait_for_quiet_host() {
  [[ "$PROFILE" == "definitive" && "$STRICT_CONTROLS" == "1" ]] || return 0
  local deadline=$(( SECONDS + QUIET_WAIT_SECONDS ))
  local load1
  while true; do
    load1="$(awk '{print $1}' /proc/loadavg)"
    if awk -v observed="$load1" -v maximum="$MAX_LOAD1" 'BEGIN { exit !(observed <= maximum) }'; then
      printf 'accepted_load1=%s\nmaximum_load1=%s\ntimestamp=%s\n' \
        "$load1" "$MAX_LOAD1" "$(date --iso-8601=seconds)" > "$HOST_DIR/quiet_host_check.txt"
      say "Host accepted for benchmark: load1=$load1 (limit=$MAX_LOAD1)"
      return 0
    fi
    (( SECONDS < deadline )) || die "Load-1 remained at $load1 (limit $MAX_LOAD1). Stop background workloads and run again."
    printf 'Waiting for an idle host: load1=%s; limit=%s\n' "$load1" "$MAX_LOAD1"
    sleep 10
  done
}

monitor_host() {
  local load1 load5 load15 _remainder frequency temperature value path
  printf 'timestamp_utc,load1,load5,load15,selected_cpu_frequency_khz,max_thermal_millicelsius\n'
  while true; do
    IFS=' ' read -r load1 load5 load15 _remainder < /proc/loadavg
    frequency=""
    [[ -r "/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq" ]] \
      && frequency="$(<"/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq")"
    temperature=""
    for path in /sys/class/thermal/thermal_zone*/temp; do
      [[ -r "$path" ]] || continue
      value="$(<"$path")"
      [[ "$value" =~ ^[0-9]+$ ]] || continue
      if [[ -z "$temperature" ]] || (( value > temperature )); then temperature="$value"; fi
    done
    printf '%s,%s,%s,%s,%s,%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "$load1" "$load5" "$load15" "$frequency" "$temperature"
    sleep "$MONITOR_INTERVAL_SECONDS"
  done
}

start_monitor() {
  monitor_host > "$HOST_DIR/host_monitor.csv" &
  MONITOR_PID="$!"
  if command -v taskset >/dev/null 2>&1 && (( ONLINE_CPUS > 1 )); then
    local monitor_cpu=0
    [[ "$CPU" != "0" ]] || monitor_cpu=1
    taskset -pc "$monitor_cpu" "$MONITOR_PID" > "$LOG_DIR/monitor_affinity.txt" 2>&1 \
      || warn "Could not pin the monitor to CPU $monitor_cpu."
  fi
}

say "Extracting the embedded pipeline into the execution snapshot"
sed -n '/^__LADC_PAYLOAD_BELOW__$/,$p' "$SELF_PATH" | tail -n +2 | base64 --decode | tar -xzf - -C "$SNAPSHOT_DIR"
find "$SNAPSHOT_DIR" -type f \( -name '._*' -o -name '.__*' -o -name '.DS_Store' \) -delete
for required in Dockerfile requirements.txt latency_artifact/pipeline.py configs/definitive.yaml configs/smoke.yaml; do
  [[ -f "$SNAPSHOT_DIR/$required" ]] || die "Incomplete embedded payload: $required"
done

cp "$SELF_PATH" "$SNAPSHOT_DIR/run_definitive_linux.sh"
capture_host before

say "Building the Docker image with pinned dependencies"
"${DOCKER[@]}" build --pull --tag "$IMAGE_TAG" "$SNAPSHOT_DIR" 2>&1 | tee "$LOG_DIR/docker_build.log"
"${DOCKER[@]}" image inspect "$IMAGE_TAG" > "$HOST_DIR/docker_image_inspect.json"
"${DOCKER[@]}" image inspect --format '{{.Id}}' "$IMAGE_TAG" > "$HOST_DIR/docker_image_id.txt"

RUN_ARGS=(
  run --rm
  --name "ladc-$PROFILE-$RUN_STAMP"
  --hostname ladc-benchmark
  --user "$(id -u):$(id -g)"
  --cpuset-cpus "$CPU"
  --network none
  --read-only
  --tmpfs "/tmp:rw,noexec,nosuid,size=512m"
  --shm-size 1g
  --pids-limit 512
  --cap-drop ALL
  --security-opt no-new-privileges:true
  -e LATENCY_DATA_DIR=/data/raw
  -e "LATENCY_OUTPUT_DIR=/artifact/results/$PROFILE"
  -v "$DATA_DIR:/data/raw:ro"
  -v "$RESULTS_ROOT:/artifact/results:rw"
)
SELINUX_ARGS=()
if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
  SELINUX_ARGS=(--security-opt label=disable)
  RUN_ARGS+=("${SELINUX_ARGS[@]}")
fi

EXPERIMENT_LOG="$LOG_DIR/experiment.log"
: > "$EXPERIMENT_LOG"

run_stage() {
  local stage="$1"
  say "Running stage '$stage' from profile '$PROFILE' on logical CPU $CPU"
  "${DOCKER[@]}" "${RUN_ARGS[@]}" "$IMAGE_TAG" "$stage" --config "configs/$PROFILE.yaml" \
    2>&1 | tee -a "$EXPERIMENT_LOG"
}

run_stage prepare
run_stage train

if [[ "$PROFILE" == "definitive" ]]; then
  say "Allowing the host to stabilize after training for at least $COOLDOWN_SECONDS seconds"
  sleep "$COOLDOWN_SECONDS"
fi
wait_for_quiet_host
capture_host pre_benchmark
start_monitor
run_stage benchmark
stop_monitor
run_stage analyze

capture_host after

say "Validating structure, counts, affinity, and thread pools"
VALIDATION_DIR="$RUN_ROOT/validation"
mkdir -p "$VALIDATION_DIR"
"${DOCKER[@]}" run --rm -i --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true --user "$(id -u):$(id -g)" \
  "${SELINUX_ARGS[@]}" \
  -v "$RESULTS_ROOT:/results:ro" -v "$SNAPSHOT_DIR:/snapshot:ro" \
  -v "$VALIDATION_DIR:/report:rw" --entrypoint python "$IMAGE_TAG" - "$PROFILE" <<'PY'
import glob
import json
import pathlib
import sys

import numpy as np
import pandas as pd
import yaml

profile = sys.argv[1]
root = pathlib.Path('/results') / profile
config = yaml.safe_load((pathlib.Path('/snapshot/configs') / f'{profile}.yaml').read_text())
models = list(config['models'])
batch_sizes = list(config['benchmark']['batch_sizes'])
fractions = list(config['benchmark']['malicious_fractions'])
repetitions = int(config['benchmark']['repetitions'])
process_runs = int(config['benchmark']['process_runs'])
evaluation_fractions = list(config['evaluation']['malicious_fractions'])

checks = []
def check(name, observed, expected):
    ok = observed == expected
    checks.append((name, ok, observed, expected))
    if not ok:
        raise AssertionError(f'{name}: observed={observed!r}, expected={expected!r}')

required = [
    root / 'processed/dataset_manifest.json',
    root / 'training_metadata.json',
    root / 'predictive_metrics.csv',
    root / 'prediction_scores.npz',
    root / 'prediction_scores_metadata.json',
    root / 'analysis/raw_combined.csv',
    root / 'analysis/timing_summary.csv',
    root / 'analysis/class_effects.csv',
    root / 'analysis/tree_path_correlations.csv',
    root / 'figures/latency_per_flow_vs_batch.png',
    root / 'figures/throughput_vs_batch.png',
]
missing = [str(path) for path in required if not path.is_file()]
check('required_files_missing', missing, [])

manifest = json.loads((root / 'processed/dataset_manifest.json').read_text())
check('feature_count', len(manifest['features']), 84)
check('label_leakage_feature_absent', 'Attempted Category' in manifest['features'], False)
check('model_file_count', len(list((root / 'models').glob('*.joblib'))), len(models))

with np.load(root / 'prediction_scores.npz') as exported:
    check('score_model_order', exported['models'].tolist(), models)
    check('validation_score_label_rows', len(exported['y_validation']), manifest['splits']['validation']['selected_rows'])
    check('test_score_label_rows', len(exported['y_test']), manifest['splits']['test']['selected_rows'])
    for model in models:
        for split in ('validation', 'test'):
            key = f'scores_{model}_{split}'
            check(f'{key}:present', key in exported.files, True)
            check(f'{key}:rows', len(exported[key]), len(exported[f'y_{split}']))
            check(f'{key}:finite', bool(np.isfinite(exported[key]).all()), True)

metrics = pd.read_csv(root / 'predictive_metrics.csv')
raw = pd.read_csv(root / 'analysis/raw_combined.csv')
summary = pd.read_csv(root / 'analysis/timing_summary.csv')
effects = pd.read_csv(root / 'analysis/class_effects.csv')
check('predictive_metric_rows', len(metrics), len(models) * (2 + len(evaluation_fractions)))
check('raw_timing_rows', len(raw), len(models) * len(batch_sizes) * len(fractions) * repetitions * process_runs)
check('timing_summary_rows', len(summary), len(models) * len(batch_sizes) * len(fractions))
check('class_effect_rows', len(effects), len(models) * len(batch_sizes))
check('independent_processes_per_effect', sorted(effects['n_independent_processes'].unique().tolist()), [process_runs])
check('raw_process_ids', sorted(raw['run_id'].unique().tolist()), list(range(process_runs)))

metadata_paths = sorted((root / 'benchmark/raw').glob('metadata_*.json'))
check('benchmark_metadata_files', len(metadata_paths), process_runs)
for path in metadata_paths:
    metadata = json.loads(path.read_text())
    check(f'{path.name}:one_cpu_affinity', metadata.get('one_cpu_affinity'), True)
    check(f'{path.name}:affinity_size', len(metadata.get('cpu_affinity') or []), 1)
    for index, pool in enumerate(metadata.get('threadpool_info', [])):
        check(f'{path.name}:threadpool_{index}', pool.get('num_threads'), 1)

lines = [
    f'LADC validation: PASS',
    f'profile={profile}',
    f'results={root}',
    '',
]
for name, ok, observed, expected in checks:
    lines.append(f'PASS {name}: observed={observed!r}; expected={expected!r}')
pathlib.Path('/report/validation_report.txt').write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
PY

say "Preparing compact package (without source data, models, and dataset.npz)"
UPLOAD="$RUN_ROOT/upload_bundle"
mkdir -p \
  "$UPLOAD/artifact_snapshot" \
  "$UPLOAD/host" \
  "$UPLOAD/logs" \
  "$UPLOAD/results/$PROFILE/analysis" \
  "$UPLOAD/results/$PROFILE/benchmark/raw" \
  "$UPLOAD/results/$PROFILE/figures" \
  "$UPLOAD/results/$PROFILE/processed" \
  "$UPLOAD/validation"

cp -R "$SNAPSHOT_DIR/." "$UPLOAD/artifact_snapshot/"
cp -R "$HOST_DIR/." "$UPLOAD/host/"
cp -R "$LOG_DIR/." "$UPLOAD/logs/"
cp -R "$VALIDATION_DIR/." "$UPLOAD/validation/"
cp -R "$RESULTS_ROOT/$PROFILE/analysis/." "$UPLOAD/results/$PROFILE/analysis/"
cp -R "$RESULTS_ROOT/$PROFILE/figures/." "$UPLOAD/results/$PROFILE/figures/"
cp "$RESULTS_ROOT/$PROFILE/predictive_metrics.csv" "$UPLOAD/results/$PROFILE/"
cp "$RESULTS_ROOT/$PROFILE/prediction_scores.npz" "$UPLOAD/results/$PROFILE/"
cp "$RESULTS_ROOT/$PROFILE/prediction_scores_metadata.json" "$UPLOAD/results/$PROFILE/"
cp "$RESULTS_ROOT/$PROFILE/training_metadata.json" "$UPLOAD/results/$PROFILE/"
cp "$RESULTS_ROOT/$PROFILE/processed/dataset_manifest.json" "$UPLOAD/results/$PROFILE/processed/"
cp "$RESULTS_ROOT/$PROFILE/benchmark/raw/"metadata_*.json "$UPLOAD/results/$PROFILE/benchmark/raw/"
cp "$RUN_ROOT/runner_version.txt" "$UPLOAD/"

find "$RESULTS_ROOT/$PROFILE/models" -type f -name '*.joblib' -print0 \
  | sort -z | xargs -0 sha256sum > "$UPLOAD/excluded_model_sha256.txt"
sha256sum "$RESULTS_ROOT/$PROFILE/processed/dataset.npz" > "$UPLOAD/excluded_dataset_npz_sha256.txt"

cat > "$UPLOAD/README_RESULTS.txt" <<EOF
LADC latency-aware IDS experiment results

Profile: $PROFILE
Run UTC: $RUN_STAMP
Selected logical CPU: $CPU
Runner version: $SCRIPT_VERSION

This compact package contains the complete source/configuration snapshot,
host and Docker metadata, continuous host monitoring, logs, validation report,
predictive metrics and scores, raw timing observations, summaries,
statistical tests, and figures.

Intentionally omitted because they are large and reproducible:
- the five original CNS2022 CICIDS2017 CSVs;
- processed/dataset.npz;
- trained models/*.joblib.

Their hashes/provenance remain recorded in the package. Keep the full run at:
$RUN_ROOT
EOF

(
  cd "$UPLOAD"
  find . -type f -print0 | sort -z | xargs -0 sha256sum
) > "$RUN_ROOT/SHA256SUMS.tmp"
mv "$RUN_ROOT/SHA256SUMS.tmp" "$UPLOAD/SHA256SUMS"
tar -C "$UPLOAD" -czf "$ARCHIVE_PATH" .
sha256sum "$ARCHIVE_PATH" > "$ARCHIVE_PATH.sha256"

say "EXECUTION COMPLETED AND VALIDATED"
printf 'Compact results package:\n  %s\n\nPackage checksum:\n  %s\n\n' \
  "$ARCHIVE_PATH" "$ARCHIVE_PATH.sha256"
printf 'Complete results (including models and processed dataset):\n  %s\n' "$RUN_ROOT"
exit 0

__LADC_PAYLOAD_BELOW__
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
