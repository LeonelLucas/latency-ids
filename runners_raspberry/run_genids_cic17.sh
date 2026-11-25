#!/usr/bin/env bash
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=latency-ids:raspberry-pi
MONITOR_PID=""
ROOT=""

say() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { echo "ERRO: $*" >&2; exit 1; }
stop_monitor() {
    if [[ -n "$MONITOR_PID" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        MONITOR_PID=""
    fi
}
trap stop_monitor EXIT
trap 'echo "Falha na linha $LINENO. Arquivos preservados em $ROOT" >&2' ERR
trap 'exit 130' INT TERM


download_verified() (
    set -Eeuo pipefail

    local url="$1"
    local output="$2"
    local expected="$3"
    local format="$4"
    local member="${5:-}"
    local tmp

    if [[ -e "$output" ]]; then
        echo "$expected  $output" | sha256sum -c -
        return
    fi

    mkdir -p "$(dirname "$output")"

    tmp=$(mktemp -d "$(dirname "$output")/.download.XXXXXX")
    trap 'rm -rf -- "$tmp"' EXIT

    curl --fail --location --retry 3 \
        --progress-bar "$url" -o "$tmp/download"

    case "$format" in
        zip)
            unzip -p "$tmp/download" "$member" > "$tmp/data"
            ;;
        gzip)
            gzip -dc "$tmp/download" > "$tmp/data"
            ;;
        raw)
            mv "$tmp/download" "$tmp/data"
            ;;
        *)
            exit 1
            ;;
    esac

    echo "$expected  $tmp/data" | sha256sum -c -

    # Publicacao atomica sem sobrescrever arquivos.
    ln "$tmp/data" "$output"

    echo "Dataset disponivel: $output"
)

run_dataset() {
    local DS="$1" SHA="$2"
    local DATA="${LATENCY_DATA_ROOT:-$REPO/../datasets}/$3"
    local CFG="configs/$4.yaml"

    cd "$REPO"

    download_verified "https://zenodo.org/api/records/21435638/files/GenIDS-CIC17.zip/content" "$DATA" "$SHA" "zip" "GenIDS-CIC17/GenIDS-CIC17.csv"
    [[ -s "$DATA" ]] || die "Dataset ausente: $DATA"
    echo "$SHA  $DATA" | sha256sum -c - || die "Hash incorreto"
    [[ -f "$CFG" ]] || die "Config ausente"

    ROOT="$REPO/multidataset-run-${DS}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    [[ "$ROOT" == "$REPO"/multidataset-run-* ]] || die "Raiz inesperada"

    R="$ROOT/results/$DS"
    L="$ROOT/logs/$DS"
    H="$ROOT/host/$DS"

    # Nunca reutilizar nem sobrescrever uma execucao
    [[ ! -e "$R" && ! -e "$L" && ! -e "$H" ]] ||
        die "Ja existem arquivos de $DS"

    if docker info >/dev/null 2>&1; then
        DOCKER=(docker)
    elif sudo -n docker info >/dev/null 2>&1; then
        DOCKER=(sudo -n docker)
    else
        die "Docker indisponivel"
    fi

    "${DOCKER[@]}" image inspect "$IMAGE" >/dev/null ||
        die "Imagem Docker ausente"

    for c in 0 1 2 3; do
        [[ "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor)" == performance ]] ||
            die "CPU$c nao esta em performance"
    done

    [[ "$(vcgencmd get_throttled)" == throttled=0x0 ]] ||
        die "Subtensao ou throttling detectado"

    mkdir "$ROOT"
    mkdir "$ROOT/results" "$ROOT/logs" "$ROOT/host"
    mkdir "$R" "$L" "$H"

    cp "$0" "$H/runner_snapshot.sh"
    cp "$CFG" "$H/config_snapshot.yaml"

    {
        echo "dataset=$DS"
        echo "source=$DATA"
        echo "source_sha256=$SHA"
        echo "config_sha256=$(sha256sum "$CFG" | cut -d' ' -f1)"
        echo "git_commit=$(git rev-parse HEAD)"
        echo "docker_image_id=$("${DOCKER[@]}" image inspect "$IMAGE" --format '{{.Id}}')"
        echo "started_utc=$(date -u +%FT%TZ)"
    } > "$H/provenance.txt"

    capture() {
        local phase="$1"
        {
            date -u --iso-8601=seconds
            uname -a
            lscpu
            free -h
            uptime
            cat /proc/loadavg
            for c in 0 1 2 3; do
                printf 'cpu%s=' "$c"
                cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor
            done
            vcgencmd measure_temp
            vcgencmd get_throttled
            vcgencmd measure_clock arm
        } > "$H/host_$phase.txt" 2>&1
    }

    monitor() {
        echo 'timestamp_utc,load1,load5,load15,cpu3_frequency_khz,max_thermal_millicelsius,throttled,mem_available_kb,swap_free_kb'
        while true; do
            read -r l1 l5 l15 _ < /proc/loadavg
            freq=$(cat /sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq)
            temp=$(cat /sys/class/thermal/thermal_zone0/temp)
            throttle=$(vcgencmd get_throttled | cut -d= -f2)
            mem=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
            swap=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)

            printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$(date -u +%FT%TZ)" "$l1" "$l5" "$l15" \
                "$freq" "$temp" "$throttle" "$mem" "$swap"
            sleep 5
        done
    }

    quiet_host() {
        local load
        for ((i=0; i<=30; i++)); do
            load=$(awk '{print $1}' /proc/loadavg)
            if awk -v x="$load" 'BEGIN {exit !(x<=0.50)}'; then
                echo "accepted_load1=$load" > "$H/quiet_host_check.txt"
                return 0
            fi
            (( i < 30 )) || break
            sleep 10
        done
        die "Carga nao estabilizou em 300 segundos"
    }

    ARGS=(
        --rm
        --user "$(id -u):$(id -g)"
        --cpuset-cpus=3
        --network none
        --read-only
        --tmpfs /tmp:rw,noexec,nosuid,size=256m
        --shm-size=256m
        --pids-limit=512
        --cap-drop ALL
        --security-opt no-new-privileges:true
    )

    MOUNTS=(
        -e "GENIDS_DATA_FILE=/data/genids/$(basename "$DATA")"
        -e "LATENCY_OUTPUT_DIR=/artifact/results/$DS"
        -v "$DATA:/data/genids/$(basename "$DATA"):ro"
        -v "$ROOT/results:/artifact/results:rw"
    )

    stage() {
        local name="$1"
        shift
        say "$DS: $name"
        "${DOCKER[@]}" run "${ARGS[@]}" "${MOUNTS[@]}" \
            "$IMAGE" "$@" 2>&1 | tee "$L/$name.log"
    }

    capture before_prepare

    say "$DS: prepare"
    "${DOCKER[@]}" run "${ARGS[@]}" "${MOUNTS[@]}" \
        --entrypoint python "$IMAGE" \
        -m latency_artifact.prepare_genids \
        --config "$CFG" 2>&1 | tee "$L/prepare.log"

    [[ -s "$R/processed/dataset.npz" ]] ||
        die "Dataset processado ausente"

    stage train train --config "$CFG"

    for model in LoR SGD NB DT RF GB AB MLP; do
        [[ -s "$R/models/$model.joblib" ]] ||
            die "Modelo ausente: $model"
    done

    say "Cooldown: 30 segundos"
    sleep 30
    quiet_host

    [[ "$(vcgencmd get_throttled)" == throttled=0x0 ]] ||
        die "Throttling antes do benchmark"

    capture before_benchmark

    monitor > "$H/benchmark_monitor.csv" &
    MONITOR_PID=$!
    taskset -pc 0 "$MONITOR_PID" \
        > "$H/monitor_affinity.txt" 2>&1 || true

    stage benchmark benchmark --config "$CFG"

    stop_monitor
    capture after_benchmark

    stage analyze analyze --config "$CFG"

    say "$DS: validacao"
    "${DOCKER[@]}" run --rm \
        --user "$(id -u):$(id -g)" \
        --network none --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=256m \
        -v "$ROOT/results:/artifact/results:ro" \
        --entrypoint python "$IMAGE" \
        -c '
import csv, glob, json, sys
import numpy as np
from pathlib import Path

root = Path("/artifact/results") / sys.argv[1]
data = np.load(root/"processed/dataset.npz", allow_pickle=False)
features = data["X_train"].shape[1]
assert features > 0

raw = sorted(glob.glob(str(root/"benchmark/raw/run_*.csv")))
assert len(raw) == 12
for filename in raw:
    with open(filename, newline="") as f:
        assert sum(1 for _ in csv.DictReader(f)) == 8640

with (root/"analysis/timing_summary.csv").open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 288
assert {r["model"] for r in rows} == {
    "LoR","SGD","NB","DT","RF","GB","AB","MLP"
}
assert {int(r["batch_size"]) for r in rows} == {
    1,8,16,32,64,100
}
assert {float(r["requested_malicious_fraction"]) for r in rows} == {
    0,0.01,0.05,0.1,0.5,1
}
assert {int(r["n"]) for r in rows} == {360}
assert {int(r["process_runs"]) for r in rows} == {12}

metadata = sorted(glob.glob(
    str(root/"benchmark/raw/metadata_*.json")
))
assert len(metadata) == 12
for filename in metadata:
    m = json.load(open(filename))
    assert m["one_cpu_affinity"] is True
    assert m["cpu_affinity"] == [3]
    assert all(int(p["num_threads"]) == 1
               for p in m["threadpool_info"])

for name in (
    "training_metadata.json",
    "predictive_metrics.csv",
    "prediction_scores.npz"
):
    assert (root/name).is_file(), name

print("VALIDATION PASS")
print("Observacoes: 103680")
print("Configuracoes: 288")
print("Features:", features)
print("CPU: 3; threads: 1")
' "$DS" 2>&1 | tee "$L/validation.log"

    say "$DS: threshold sensitivity"
    "${DOCKER[@]}" run --rm \
        --user "$(id -u):$(id -g)" \
        --network none --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=256m \
        --entrypoint python \
        -v "$R:/artifact/results/definitive:rw" \
        "$IMAGE" scripts/analyze_thresholds.py \
        /artifact/results/definitive/prediction_scores.npz \
        --output /artifact/results/definitive/analysis/threshold_sensitivity.csv \
        --seed 20260719 --max-samples 100000 \
        2>&1 | tee "$L/threshold_sensitivity.log"

    [[ -s "$R/analysis/threshold_sensitivity.csv" ]] ||
        die "Analise de limiar ausente"

    if awk -F, 'NR>1 && $7!="0x0" {bad=1} END {exit !bad}' \
        "$H/benchmark_monitor.csv"; then
        echo "AVISO: throttling registrado" \
            | tee "$H/throttling_warning.txt"
    fi

    echo "completed_utc=$(date -u +%FT%TZ)" > "$H/completed.txt"
    say "$DS FINALIZADO"
}

run_dataset \
    genids_cic17 \
    946c98e3562f2c7e2a1c6cea9d5d180db391a1b7390e76bb694b46f89bddf5b9 \
    GenIDS-CIC17.csv \
    genids_cic17
