#!/usr/bin/env bash
#
# Definitive multi-dataset runner for the latency-aware ML-IDS experiments.
#
# Currently supported:
#   - CICIDS2017 (CNS2022 corrected release)
#   - GenIDS-CIC17
#   - GenIDS-UNSW15
#
# Each dataset is prepared, trained, benchmarked, analyzed, and validated
# independently. Results and trained models are never shared between datasets.
#
# Future datasets can be added without changing the original pipeline.py or
# run_definitive_linux.sh.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="2026-09-26.1"

readonly CICIDS2017_URL="https://intrusion-detection.distrinet-research.be/CNS2022/Datasets/CICIDS2017_improved.zip"
readonly CICIDS2017_ARCHIVE_SHA256="97fdb91d339e2d8cf5627f981b831e5e7e400b981c58181c451a38fd03c48883"
readonly CICIDS2017_MONDAY_SHA256="51fe5dc962626efb4ae70dce0303072fb780da0932822b651202ee9c2fbc1aff"
readonly CICIDS2017_TUESDAY_SHA256="e2a0a5b631dfc6b455cc9f9a88b944110637d70a7f74171473925f76f38b6b0c"
readonly CICIDS2017_WEDNESDAY_SHA256="bf46c5f3c792e8817381f724511229569606918eaf07ac986d7a2592b6341bc2"
readonly CICIDS2017_THURSDAY_SHA256="78a4d11eaf473d099e30e71ddb01e0f38218e844c0a9cdd36602145d674af482"
readonly CICIDS2017_FRIDAY_SHA256="ebd499e6f23bd59f9cb81bec28178491b02b925fa5640a24215c9437d79482d0"

show_logo() {
    cat <<'EOF'

  ___   ____    ____  
 |_ _| |  _ \  / ___| 
  | |  | | | | \___ \ 
  | |  | |_| |  ___) |
 |___| |____/  |____/ 

  _____ ____      _    ____  _____        ___  _____ _____     
 |_   _|  _ \    / \  |  _ \| ____|      / _ \|  ___|  ___|___ 
   | | | |_) |  / _ \ | | | |  _| _____| | | | |_  | |_ / __|
   | | |  _ <  / ___ \| |_| | |__|_____| |_| |  _| |  _|\__ \
   |_| |_| \_\/_/   \_\____/|_____|     \___/|_|   |_|  |___/

                         IDS TRADE-OFFs
              Reproducible Multi-Dataset ML-IDS Evaluation

EOF
}

say() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
    printf '\nWARNING: %s\n' "$*" >&2
}

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

MONITOR_PID=""

stop_monitor() {
    if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" >/dev/null 2>&1; then
        kill "$MONITOR_PID" >/dev/null 2>&1 || true
        wait "$MONITOR_PID" >/dev/null 2>&1 || true
    fi
    MONITOR_PID=""
}

on_error() {
    local line="$1"
    local status="$2"
    printf '\nERROR at line %s (status %s). Partial files were preserved.\n' \
        "$line" "$status" >&2
}

trap 'on_error "$LINENO" "$?"' ERR
trap 'stop_monitor' EXIT
trap 'printf "\nExecution interrupted; partial files were preserved.\n" >&2; exit 130' INT TERM

START_DIR="$(pwd -P)"
RUN_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"

RUN_ROOT="${TRADEOFF_MULTI_OUTPUT_DIR:-$START_DIR/multidataset-run-$RUN_STAMP}"

RESULTS_ROOT="$RUN_ROOT/results"
LOG_ROOT="$RUN_ROOT/logs"
HOST_ROOT="$RUN_ROOT/host"

CICIDS2017_RESULTS="$RESULTS_ROOT/cicids2017"
GENIDS_CIC17_RESULTS="$RESULTS_ROOT/genids_cic17"
GENIDS_UNSW15_RESULTS="$RESULTS_ROOT/genids_unsw15"
GENIDS_CIC18_RESULTS="$RESULTS_ROOT/genids_cic18"

CICIDS2017_DATA_DIR="${TRADEOFF_CICIDS2017_DATA_DIR:-$START_DIR/../datasets/CICIDS2017}"
GENIDS_CIC17_DATA_FILE="${TRADEOFF_GENIDS_CIC17_DATA_FILE:-$START_DIR/../datasets/GenIDS-CIC17.csv}"
GENIDS_UNSW15_DATA_FILE="${TRADEOFF_GENIDS_UNSW15_DATA_FILE:-$START_DIR/../datasets/GenIDS-UNSW15.csv}"
GENIDS_CIC18_DATA_FILE="${TRADEOFF_GENIDS_CIC18_DATA_FILE:-$START_DIR/../datasets/GenIDS-CIC18.csv}"

MAX_LOAD1="${TRADEOFF_MAX_LOAD1:-0.50}"
COOLDOWN_SECONDS="${TRADEOFF_COOLDOWN_SECONDS:-30}"
QUIET_WAIT_SECONDS="${TRADEOFF_QUIET_WAIT_SECONDS:-300}"
MONITOR_INTERVAL_SECONDS="${TRADEOFF_MONITOR_INTERVAL_SECONDS:-2}"

[[ "$(uname -s)" == "Linux" ]] || die "This runner must execute on Linux."
(( BASH_VERSINFO[0] >= 4 )) || die "Bash 4 or newer is required."

[[ ! -e "$RUN_ROOT" ]] || die "Run directory already exists: $RUN_ROOT"

mkdir -p \
    "$CICIDS2017_RESULTS" \
    "$GENIDS_CIC17_RESULTS" \
    "$GENIDS_UNSW15_RESULTS" \
    "$GENIDS_CIC18_RESULTS" \
    "$LOG_ROOT/cicids2017" \
    "$LOG_ROOT/genids_cic17" \
    "$LOG_ROOT/genids_unsw15" \
    "$LOG_ROOT/genids_cic18" \
    "$HOST_ROOT/cicids2017" \
    "$HOST_ROOT/genids_cic17" \
    "$HOST_ROOT/genids_unsw15" \
    "$HOST_ROOT/genids_cic18"

printf '%s\n' "$SCRIPT_VERSION" > "$RUN_ROOT/runner_version.txt"

say "Multi-dataset execution directory created"
printf 'Run root:          %s\n' "$RUN_ROOT"
printf 'CICIDS2017:        %s\n' "$CICIDS2017_RESULTS"
printf 'GenIDS-CIC17:      %s\n' "$GENIDS_CIC17_RESULTS"
printf 'GenIDS-UNSW15:     %s\n' "$GENIDS_UNSW15_RESULTS"
printf 'GenIDS-CIC18:      %s\n' "$GENIDS_CIC18_RESULTS"

# ---------------------------------------------------------------------------
# Docker and experimental host controls
# ---------------------------------------------------------------------------

SUDO=()
if (( EUID != 0 )); then
    command -v sudo >/dev/null 2>&1 && SUDO=(sudo)
fi

DOCKER=()

configure_docker() {
    command -v docker >/dev/null 2>&1 || die "Docker CLI was not found."

    if docker info >/dev/null 2>&1; then
        DOCKER=(docker)
    elif (( ${#SUDO[@]} > 0 )) && "${SUDO[@]}" docker info >/dev/null 2>&1; then
        DOCKER=("${SUDO[@]}" docker)
    else
        die "Docker was found, but access to the Docker daemon is unavailable."
    fi
}

configure_docker

ONLINE_CPUS="$(nproc --all)"
(( ONLINE_CPUS >= 1 )) || die "Could not determine the number of logical CPUs."

DEFAULT_CPU="$(( ONLINE_CPUS - 1 ))"
CPU="${TRADEOFF_CPU:-$DEFAULT_CPU}"

[[ "$CPU" =~ ^[0-9]+$ ]] || die "TRADEOFF_CPU must be a non-negative integer."
[[ -d "/sys/devices/system/cpu/cpu$CPU" ]] || die "Logical CPU $CPU does not exist."

if [[ -r "/sys/devices/system/cpu/cpu$CPU/online" ]]; then
    [[ "$(<"/sys/devices/system/cpu/cpu$CPU/online")" == "1" ]] \
        || die "Logical CPU $CPU is offline."
fi

GOVERNOR_FILE="/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor"

if [[ ! -r "$GOVERNOR_FILE" ]]; then
    die "Could not verify the CPU governor: $GOVERNOR_FILE"
fi

GOVERNOR="$(<"$GOVERNOR_FILE")"

if [[ "$GOVERNOR" != "performance" ]]; then
    die "CPU $CPU uses governor '$GOVERNOR'; 'performance' is required."
fi

wait_for_quiet_host() {
    local dataset="$1"
    local host_dir="$HOST_ROOT/$dataset"
    local deadline=$(( SECONDS + QUIET_WAIT_SECONDS ))
    local load1

    while true; do
        load1="$(awk '{print $1}' /proc/loadavg)"

        if awk -v observed="$load1" -v maximum="$MAX_LOAD1" \
            'BEGIN { exit !(observed <= maximum) }'; then

            printf 'accepted_load1=%s\nmaximum_load1=%s\ntimestamp=%s\n' \
                "$load1" \
                "$MAX_LOAD1" \
                "$(date --iso-8601=seconds)" \
                > "$host_dir/quiet_host_check.txt"

            say "$dataset: host accepted for benchmark: load1=$load1 (limit=$MAX_LOAD1)"
            return 0
        fi

        (( SECONDS < deadline )) \
            || die "$dataset: load-1 remained at $load1 (limit $MAX_LOAD1)."

        printf '%s: waiting for idle host: load1=%s; limit=%s\n' \
            "$dataset" "$load1" "$MAX_LOAD1"

        sleep 10
    done
}

monitor_host() {
    local load1 load5 load15 remainder frequency temperature value path

    printf 'timestamp_utc,load1,load5,load15,selected_cpu_frequency_khz,max_thermal_millicelsius\n'

    while true; do
        IFS=' ' read -r load1 load5 load15 remainder < /proc/loadavg

        frequency=""
        if [[ -r "/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq" ]]; then
            frequency="$(<"/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq")"
        fi

        temperature=""

        for path in /sys/class/thermal/thermal_zone*/temp; do
            [[ -r "$path" ]] || continue
            value="$(<"$path")"
            [[ "$value" =~ ^[0-9]+$ ]] || continue

            if [[ -z "$temperature" ]] || (( value > temperature )); then
                temperature="$value"
            fi
        done

        printf '%s,%s,%s,%s,%s,%s\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            "$load1" "$load5" "$load15" "$frequency" "$temperature"

        sleep "$MONITOR_INTERVAL_SECONDS"
    done
}

start_monitor() {
    local dataset="$1"
    local destination="$HOST_ROOT/$dataset/benchmark_monitor.csv"

    stop_monitor
    monitor_host > "$destination" &
    MONITOR_PID=$!
}

capture_host() {
    local dataset="$1"
    local phase="$2"
    local destination="$HOST_ROOT/$dataset/host_${phase}.txt"

    (
        set +e

        printf 'runner_version=%s\n' "$SCRIPT_VERSION"
        printf 'dataset=%s\n' "$dataset"
        printf 'selected_cpu=%s\n' "$CPU"
        printf 'run_root=%s\n' "$RUN_ROOT"
        printf 'max_load1=%s\n' "$MAX_LOAD1"

        date --iso-8601=seconds
        uname -a

        printf '\nlscpu\n'
        lscpu

        printf '\nnproc\n'
        nproc
        nproc --all

        printf '\n/proc/loadavg\n'
        cat /proc/loadavg

        printf '\nfree\n'
        free -h

        printf '\nselected_cpu_governor\n'
        cat "$GOVERNOR_FILE"

        printf '\nuptime\n'
        uptime

        printf '\ntop_cpu_processes\n'
        ps -eo pid,psr,pcpu,pmem,comm --sort=-pcpu | head -n 25

        printf '\ndocker_version\n'
        "${DOCKER[@]}" version
    ) > "$destination" 2>&1
}

say "Experimental controls verified"
printf 'Selected CPU:      %s\n' "$CPU"
printf 'CPU governor:      %s\n' "$GOVERNOR"
printf 'Maximum load-1:    %s\n' "$MAX_LOAD1"
printf 'Cooldown:          %s seconds\n' "$COOLDOWN_SECONDS"

# ---------------------------------------------------------------------------
# Dataset validation
# ---------------------------------------------------------------------------

verify_sha256() {
    local file="$1"
    local expected="$2"
    local observed

    [[ -f "$file" ]] || die "Required file not found: $file"

    observed="$(sha256sum "$file" | awk '{print $1}')"

    [[ "$observed" == "$expected" ]] \
        || die "SHA-256 mismatch for $file: expected $expected, got $observed"
}

validate_cicids2017() {
    say "Validating CICIDS2017 input files"

    verify_sha256 \
        "$CICIDS2017_DATA_DIR/monday.csv" \
        "$CICIDS2017_MONDAY_SHA256"

    verify_sha256 \
        "$CICIDS2017_DATA_DIR/tuesday.csv" \
        "$CICIDS2017_TUESDAY_SHA256"

    verify_sha256 \
        "$CICIDS2017_DATA_DIR/wednesday.csv" \
        "$CICIDS2017_WEDNESDAY_SHA256"

    verify_sha256 \
        "$CICIDS2017_DATA_DIR/thursday.csv" \
        "$CICIDS2017_THURSDAY_SHA256"

    verify_sha256 \
        "$CICIDS2017_DATA_DIR/friday.csv" \
        "$CICIDS2017_FRIDAY_SHA256"

    say "CICIDS2017 input validation passed"
}

validate_genids_cic17() {
    local expected_sha256
    local observed_sha256

    expected_sha256="946c98e3562f2c7e2a1c6cea9d5d180db391a1b7390e76bb694b46f89bddf5b9"

    say "Validating GenIDS-CIC17 input file"

    [[ -f "$GENIDS_CIC17_DATA_FILE" ]] \
        || die "GenIDS-CIC17 file not found: $GENIDS_CIC17_DATA_FILE"

    observed_sha256="$(sha256sum "$GENIDS_CIC17_DATA_FILE" | awk '{print $1}')"

    [[ "$observed_sha256" == "$expected_sha256" ]] \
        || die "SHA-256 mismatch for GenIDS-CIC17: expected $expected_sha256, got $observed_sha256"

    say "GenIDS-CIC17 input validation passed"
}

validate_genids_unsw15() {
    local expected_sha256
    local observed_sha256

    expected_sha256="2437a5fb6ae6f37d47e24e2fc4ee2df243248679f412a0f3dd1ffd7e757ddb1e"

    say "Validating GenIDS-UNSW15 input file"

    [[ -f "$GENIDS_UNSW15_DATA_FILE" ]] \
        || die "GenIDS-UNSW15 file not found: $GENIDS_UNSW15_DATA_FILE"

    observed_sha256="$(sha256sum "$GENIDS_UNSW15_DATA_FILE" | awk '{print $1}')"

    [[ "$observed_sha256" == "$expected_sha256" ]] \
        || die "SHA-256 mismatch for GenIDS-UNSW15: expected $expected_sha256, got $observed_sha256"

    say "GenIDS-UNSW15 input validation passed"
}

validate_genids_cic18() {
    local expected_sha256
    local observed_sha256

    expected_sha256="b67bd1437ad1e4078296b7196946c4522390ed8f640ea1298f59b19b2923d7e2"

    say "Validating GenIDS-CIC18 input file"

    [[ -f "$GENIDS_CIC18_DATA_FILE" ]] \
        || die "GenIDS-CIC18 file not found: $GENIDS_CIC18_DATA_FILE"

    observed_sha256="$(sha256sum "$GENIDS_CIC18_DATA_FILE" | awk '{print $1}')"

    [[ "$observed_sha256" == "$expected_sha256" ]] \
        || die "SHA-256 mismatch for GenIDS-CIC18: expected $expected_sha256, got $observed_sha256"

    say "GenIDS-CIC18 input validation passed"
}

# ---------------------------------------------------------------------------
# Reproducible Docker image
# ---------------------------------------------------------------------------

IMAGE_TAG="latency-ids-multidataset:$RUN_STAMP"

build_experiment_image() {
    say "Building common Docker image for all datasets"

    "${DOCKER[@]}" build \
        --pull \
        --tag "$IMAGE_TAG" \
        "$START_DIR" \
        2>&1 | tee "$LOG_ROOT/docker_build.log"

    "${DOCKER[@]}" image inspect "$IMAGE_TAG" \
        > "$LOG_ROOT/docker_image_inspect.json"

    say "Docker image built: $IMAGE_TAG"
}

docker_common_args() {
    printf '%s\n' \
        "--rm" \
        "--user" "$(id -u):$(id -g)" \
        "--cpuset-cpus=$CPU" \
        "--network" "none" \
        "--read-only" \
        "--tmpfs" "/tmp:rw,noexec,nosuid,size=512m" \
        "--shm-size" "1g" \
        "--pids-limit" "512" \
        "--cap-drop" "ALL" \
        "--security-opt" "no-new-privileges:true"
}

# ---------------------------------------------------------------------------
# CICIDS2017 definitive experiment
# ---------------------------------------------------------------------------

run_cicids2017() {
    local dataset="cicids2017"
    local result_dir="$CICIDS2017_RESULTS"
    local log_dir="$LOG_ROOT/$dataset"
    local -a common_args

    mapfile -t common_args < <(docker_common_args)

    say "Starting CICIDS2017 definitive experiment"

    capture_host "$dataset" "before_prepare"

    say "CICIDS2017: preparing dataset"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e LATENCY_DATA_DIR=/data/raw \
        -e LATENCY_OUTPUT_DIR=/artifact/results/cicids2017 \
        -v "$CICIDS2017_DATA_DIR:/data/raw:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        prepare --config configs/definitive.yaml \
        2>&1 | tee "$log_dir/prepare.log"

    say "CICIDS2017: training models"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e LATENCY_DATA_DIR=/data/raw \
        -e LATENCY_OUTPUT_DIR=/artifact/results/cicids2017 \
        -v "$CICIDS2017_DATA_DIR:/data/raw:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        train --config configs/definitive.yaml \
        2>&1 | tee "$log_dir/train.log"

    say "CICIDS2017: cooldown for ${COOLDOWN_SECONDS}s"
    sleep "$COOLDOWN_SECONDS"

    wait_for_quiet_host "$dataset"
    capture_host "$dataset" "before_benchmark"

    say "CICIDS2017: starting benchmark"
    start_monitor "$dataset"

    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --name "cicids2017-benchmark-$RUN_STAMP" \
        --hostname tradeoff-benchmark \
        -e LATENCY_DATA_DIR=/data/raw \
        -e LATENCY_OUTPUT_DIR=/artifact/results/cicids2017 \
        -v "$CICIDS2017_DATA_DIR:/data/raw:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        benchmark --config configs/definitive.yaml \
        2>&1 | tee "$log_dir/benchmark.log"

    stop_monitor
    capture_host "$dataset" "after_benchmark"

    say "CICIDS2017: analyzing benchmark"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e LATENCY_DATA_DIR=/data/raw \
        -e LATENCY_OUTPUT_DIR=/artifact/results/cicids2017 \
        -v "$CICIDS2017_DATA_DIR:/data/raw:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        analyze --config configs/definitive.yaml \
        2>&1 | tee "$log_dir/analyze.log"

    [[ -f "$result_dir/processed/dataset.npz" ]] \
        || die "CICIDS2017 processed dataset was not created."

    [[ -f "$result_dir/analysis/timing_summary.csv" ]] \
        || die "CICIDS2017 timing summary was not created."

    say "CICIDS2017 definitive experiment completed"
}

# ---------------------------------------------------------------------------
# GenIDS-CIC17 definitive experiment
# ---------------------------------------------------------------------------

run_genids_cic17() {
    local dataset="genids_cic17"
    local result_dir="$GENIDS_CIC17_RESULTS"
    local log_dir="$LOG_ROOT/$dataset"
    local genids_data_dir
    local genids_data_name
    local -a common_args

    genids_data_dir="$(cd "$(dirname "$GENIDS_CIC17_DATA_FILE")" && pwd -P)"
    genids_data_name="$(basename "$GENIDS_CIC17_DATA_FILE")"

    mapfile -t common_args < <(docker_common_args)

    say "Starting GenIDS-CIC17 definitive experiment"

    capture_host "$dataset" "before_prepare"

    say "GenIDS-CIC17: preparing dataset"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --entrypoint python \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic17 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        -m latency_artifact.prepare_genids \
        --config configs/genids_cic17.yaml \
        2>&1 | tee "$log_dir/prepare.log"

    say "GenIDS-CIC17: training models"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic17 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        train --config configs/genids_cic17.yaml \
        2>&1 | tee "$log_dir/train.log"

    say "GenIDS-CIC17: cooldown for ${COOLDOWN_SECONDS}s"
    sleep "$COOLDOWN_SECONDS"

    wait_for_quiet_host "$dataset"
    capture_host "$dataset" "before_benchmark"

    say "GenIDS-CIC17: starting benchmark"
    start_monitor "$dataset"

    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --name "genids-cic17-benchmark-$RUN_STAMP" \
        --hostname tradeoff-benchmark \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic17 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        benchmark --config configs/genids_cic17.yaml \
        2>&1 | tee "$log_dir/benchmark.log"

    stop_monitor
    capture_host "$dataset" "after_benchmark"

    say "GenIDS-CIC17: analyzing benchmark"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic17 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        analyze --config configs/genids_cic17.yaml \
        2>&1 | tee "$log_dir/analyze.log"

    [[ -f "$result_dir/processed/dataset.npz" ]] \
        || die "GenIDS-CIC17 processed dataset was not created."

    [[ -f "$result_dir/analysis/timing_summary.csv" ]] \
        || die "GenIDS-CIC17 timing summary was not created."

    say "GenIDS-CIC17 definitive experiment completed"
}

# ---------------------------------------------------------------------------
# GenIDS-UNSW15 definitive experiment
# ---------------------------------------------------------------------------

run_genids_unsw15() {
    local dataset="genids_unsw15"
    local result_dir="$GENIDS_UNSW15_RESULTS"
    local log_dir="$LOG_ROOT/$dataset"
    local genids_data_dir
    local genids_data_name
    local -a common_args

    genids_data_dir="$(cd "$(dirname "$GENIDS_UNSW15_DATA_FILE")" && pwd -P)"
    genids_data_name="$(basename "$GENIDS_UNSW15_DATA_FILE")"

    mapfile -t common_args < <(docker_common_args)

    say "Starting GenIDS-UNSW15 definitive experiment"

    capture_host "$dataset" "before_prepare"

    say "GenIDS-UNSW15: preparing dataset"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --entrypoint python \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_unsw15 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        -m latency_artifact.prepare_genids \
        --config configs/genids_unsw15.yaml \
        2>&1 | tee "$log_dir/prepare.log"

    say "GenIDS-UNSW15: training models"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_unsw15 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        train --config configs/genids_unsw15.yaml \
        2>&1 | tee "$log_dir/train.log"

    say "GenIDS-UNSW15: cooldown for ${COOLDOWN_SECONDS}s"
    sleep "$COOLDOWN_SECONDS"

    wait_for_quiet_host "$dataset"
    capture_host "$dataset" "before_benchmark"

    say "GenIDS-UNSW15: starting benchmark"
    start_monitor "$dataset"

    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --name "genids-unsw15-benchmark-$RUN_STAMP" \
        --hostname tradeoff-benchmark \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_unsw15 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        benchmark --config configs/genids_unsw15.yaml \
        2>&1 | tee "$log_dir/benchmark.log"

    stop_monitor
    capture_host "$dataset" "after_benchmark"

    say "GenIDS-UNSW15: analyzing benchmark"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_unsw15 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        analyze --config configs/genids_unsw15.yaml \
        2>&1 | tee "$log_dir/analyze.log"

    [[ -f "$result_dir/processed/dataset.npz" ]] \
        || die "GenIDS-UNSW15 processed dataset was not created."

    [[ -f "$result_dir/analysis/timing_summary.csv" ]] \
        || die "GenIDS-UNSW15 timing summary was not created."

    say "GenIDS-UNSW15 definitive experiment completed"
}

# ---------------------------------------------------------------------------
# GenIDS-CIC18 definitive experiment
# ---------------------------------------------------------------------------

run_genids_cic18() {
    local dataset="genids_cic18"
    local result_dir="$GENIDS_CIC18_RESULTS"
    local log_dir="$LOG_ROOT/$dataset"
    local genids_data_dir
    local genids_data_name
    local -a common_args

    genids_data_dir="$(cd "$(dirname "$GENIDS_CIC18_DATA_FILE")" && pwd -P)"
    genids_data_name="$(basename "$GENIDS_CIC18_DATA_FILE")"

    mapfile -t common_args < <(docker_common_args)

    say "Starting GenIDS-CIC18 definitive experiment"

    capture_host "$dataset" "before_prepare"

    say "GenIDS-CIC18: preparing dataset"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --entrypoint python \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic18 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        -m latency_artifact.prepare_genids \
        --config configs/genids_cic18.yaml \
        2>&1 | tee "$log_dir/prepare.log"

    say "GenIDS-CIC18: training models"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic18 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        train --config configs/genids_cic18.yaml \
        2>&1 | tee "$log_dir/train.log"

    say "GenIDS-CIC18: cooldown for ${COOLDOWN_SECONDS}s"
    sleep "$COOLDOWN_SECONDS"

    wait_for_quiet_host "$dataset"
    capture_host "$dataset" "before_benchmark"

    say "GenIDS-CIC18: starting benchmark"
    start_monitor "$dataset"

    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        --name "genids-cic18-benchmark-$RUN_STAMP" \
        --hostname tradeoff-benchmark \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic18 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        benchmark --config configs/genids_cic18.yaml \
        2>&1 | tee "$log_dir/benchmark.log"

    stop_monitor
    capture_host "$dataset" "after_benchmark"

    say "GenIDS-CIC18: analyzing benchmark"
    "${DOCKER[@]}" run \
        "${common_args[@]}" \
        -e GENIDS_DATA_FILE="/data/genids/$genids_data_name" \
        -e LATENCY_OUTPUT_DIR=/artifact/results/genids_cic18 \
        -v "$genids_data_dir:/data/genids:ro" \
        -v "$RESULTS_ROOT:/artifact/results:rw" \
        "$IMAGE_TAG" \
        analyze --config configs/genids_cic18.yaml \
        2>&1 | tee "$log_dir/analyze.log"

    [[ -f "$result_dir/processed/dataset.npz" ]] \
        || die "GenIDS-CIC18 processed dataset was not created."

    [[ -f "$result_dir/analysis/timing_summary.csv" ]] \
        || die "GenIDS-CIC18 timing summary was not created."

    say "GenIDS-CIC18 definitive experiment completed"
}

# ---------------------------------------------------------------------------
# Final validation
# ---------------------------------------------------------------------------

validate_experiment_output() {
    local dataset="$1"
    local result_dir="$2"
    local expected_features="$3"

    say "$dataset: validating definitive outputs"

    [[ -f "$result_dir/processed/dataset.npz" ]] \
        || die "$dataset: missing processed/dataset.npz"

    [[ -f "$result_dir/training_metadata.json" ]] \
        || die "$dataset: missing training_metadata.json"

    [[ -f "$result_dir/predictive_metrics.csv" ]] \
        || die "$dataset: missing predictive_metrics.csv"

    [[ -f "$result_dir/analysis/timing_summary.csv" ]] \
        || die "$dataset: missing analysis/timing_summary.csv"

    local run_count
    run_count="$(
        find "$result_dir/benchmark/raw" \
            -maxdepth 1 -type f -name 'run_*.csv' | wc -l
    )"

    [[ "$run_count" -eq 12 ]] \
        || die "$dataset: expected 12 benchmark run CSVs, found $run_count"

    "${DOCKER[@]}" run \
        --rm \
        --user "$(id -u):$(id -g)" \
        --network none \
        --read-only \
        --tmpfs "/tmp:rw,noexec,nosuid,size=256m" \
        -v "$RESULTS_ROOT:/artifact/results:ro" \
        --entrypoint python \
        "$IMAGE_TAG" \
        -c "
import csv
import glob
import json
import numpy as np
from pathlib import Path

root = Path('/artifact/results/$dataset')
expected_features = int('$expected_features')

data = np.load(root / 'processed' / 'dataset.npz', allow_pickle=False)

feature_count = int(data['X_train'].shape[1])
assert feature_count == expected_features, (
    f'expected {expected_features} features, got {feature_count}'
)

run_files = sorted(glob.glob(str(root / 'benchmark' / 'raw' / 'run_*.csv')))
assert len(run_files) == 12, f'expected 12 run files, got {len(run_files)}'

total_rows = 0
for filename in run_files:
    with open(filename, newline='') as handle:
        rows = sum(1 for _ in csv.DictReader(handle))
    assert rows == 8640, f'{filename}: expected 8640 rows, got {rows}'
    total_rows += rows

assert total_rows == 103680, (
    f'expected 103680 benchmark observations, got {total_rows}'
)

summary = root / 'analysis' / 'timing_summary.csv'
with summary.open(newline='') as handle:
    rows = list(csv.DictReader(handle))

assert len(rows) == 288, (
    f'expected 288 timing-summary rows, got {len(rows)}'
)

models = sorted({row['model'] for row in rows})
expected_models = sorted(['LoR', 'SGD', 'NB', 'DT', 'RF', 'GB', 'AB', 'MLP'])
assert models == expected_models, (models, expected_models)

batches = sorted({int(row['batch_size']) for row in rows})
assert batches == [1, 8, 16, 32, 64, 100], batches

fractions = sorted({float(row['requested_malicious_fraction']) for row in rows})
assert fractions == [0.0, 0.01, 0.05, 0.1, 0.5, 1.0], fractions

assert {int(row['n']) for row in rows} == {360}
assert {int(row['process_runs']) for row in rows} == {12}

print(
    f'VALIDATION OK: $dataset; '
    f'features={feature_count}; '
    f'benchmark_rows={total_rows}; '
    f'timing_summary_rows={len(rows)}'
)
" 2>&1 | tee "$LOG_ROOT/$dataset/validation.log"

    say "$dataset: definitive output validation passed"
}

run_threshold_sensitivity() {
    local dataset="$1"
    local result_dir="$2"

    local scores="$result_dir/prediction_scores.npz"
    local output="$result_dir/analysis/threshold_sensitivity.csv"

    [[ -f "$scores" ]] \
        || die "$dataset: prediction scores not found: $scores"

    mkdir -p "$result_dir/analysis"

    say "$dataset: running threshold sensitivity analysis"

    python3 scripts/analyze_thresholds.py \
        "$scores" \
        --output "$output" \
        2>&1 | tee "$LOG_ROOT/$dataset/threshold_sensitivity.log"

    [[ -s "$output" ]] \
        || die "$dataset: threshold sensitivity output was not created"

    say "$dataset: threshold sensitivity analysis completed"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

main() {
    show_logo
    say "Starting definitive multi-dataset experiment"
    printf 'Runner version:    %s\n' "$SCRIPT_VERSION"
    printf 'Execution root:    %s\n' "$RUN_ROOT"

    validate_cicids2017
    validate_genids_cic17
    validate_genids_unsw15
    validate_genids_cic18

    build_experiment_image

    run_cicids2017
    validate_experiment_output \
        "cicids2017" \
        "$CICIDS2017_RESULTS" \
        "84"
    run_threshold_sensitivity "cicids2017" "$CICIDS2017_RESULTS"

    say "CICIDS2017 finished; preparing for the next dataset"
    sleep "$COOLDOWN_SECONDS"

    run_genids_cic17
    validate_experiment_output \
        "genids_cic17" \
        "$GENIDS_CIC17_RESULTS" \
        "57"
    run_threshold_sensitivity "genids_cic17" "$GENIDS_CIC17_RESULTS"

    say "GenIDS-CIC17 finished; preparing for the next dataset"
    sleep "$COOLDOWN_SECONDS"

    run_genids_unsw15
    validate_experiment_output \
        "genids_unsw15" \
        "$GENIDS_UNSW15_RESULTS" \
        "63"
    run_threshold_sensitivity "genids_unsw15" "$GENIDS_UNSW15_RESULTS"

    say "GenIDS-UNSW15 finished; preparing for the next dataset"
    sleep "$COOLDOWN_SECONDS"

    run_genids_cic18
    validate_experiment_output \
        "genids_cic18" \
        "$GENIDS_CIC18_RESULTS" \
        "63"
    run_threshold_sensitivity "genids_cic18" "$GENIDS_CIC18_RESULTS"

    say "All definitive multi-dataset experiments completed successfully"
    printf '\nResults:\n'
    printf '  CICIDS2017:   %s\n' "$CICIDS2017_RESULTS"
    printf '  GenIDS-CIC17: %s\n' "$GENIDS_CIC17_RESULTS"
    printf '  GenIDS-UNSW15: %s\n' "$GENIDS_UNSW15_RESULTS"
    printf '  GenIDS-CIC18:  %s\n' "$GENIDS_CIC18_RESULTS"
}

main "$@"
