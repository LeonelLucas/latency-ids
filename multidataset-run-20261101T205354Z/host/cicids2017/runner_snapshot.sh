#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/home/lucasleonel/latency-ids
IMAGE=latency-ids:raspberry-pi
DS=cicids2017
CFG=configs/definitive.yaml
DATA=/home/lucasleonel/datasets/CICIDS2017

MONITOR_PID=""
ROOT=""
R=""
L=""
H=""

say() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
}

die() {
    echo "ERRO: $*" >&2
    exit 1
}

stop_monitor() {
    if [[ -n "$MONITOR_PID" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        MONITOR_PID=""
    fi
}

trap stop_monitor EXIT
trap 'echo "Falha na linha $LINENO. Resultados preservados em $R" >&2' ERR
trap 'exit 130' INT TERM

cd "$REPO"

# Verificacoes antes de criar qualquer diretorio.
[[ -f "$CFG" ]] || die "Configuracao ausente"
[[ -f raspberry_multidataset_active_root.txt ]] ||
    die "Arquivo da raiz ativa ausente"

ROOT=$(cat raspberry_multidataset_active_root.txt)

[[ "$ROOT" == "$REPO"/multidataset-run-* ]] ||
    die "Raiz experimental inesperada"

for previous in genids_cic18 genids_unsw15 genids_cic17; do
    [[ -f "$ROOT/host/$previous/completed.txt" ]] ||
        die "Experimento anterior nao concluido: $previous"
done

R="$ROOT/results/$DS"
L="$ROOT/logs/$DS"
H="$ROOT/host/$DS"

[[ ! -e "$R" && ! -e "$L" && ! -e "$H" ]] ||
    die "Diretorios CICIDS2017 ja existem. Nada sera sobrescrito."

for day in monday tuesday wednesday thursday friday; do
    [[ -s "$DATA/$day.csv" ]] ||
        die "CSV ausente: $day.csv"
done

if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
elif sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo -n docker)
else
    die "Docker indisponivel"
fi

"${DOCKER[@]}" image inspect "$IMAGE" >/dev/null ||
    die "Imagem Docker ausente"

# Confirmar configuracao definitiva.
python3 - <<'PY'
from pathlib import Path
import yaml

c = yaml.safe_load(Path("configs/definitive.yaml").read_text())

assert c["models"] == ["LoR", "SGD", "NB", "DT", "RF", "GB", "AB", "MLP"]
assert c["benchmark"]["batch_sizes"] == [1, 8, 16, 32, 64, 100]
assert c["benchmark"]["malicious_fractions"] == [0.0, 0.01, 0.05, 0.1, 0.5, 1.0]
assert c["benchmark"]["repetitions"] == 30
assert c["benchmark"]["process_runs"] == 12
assert c["benchmark"]["warmup"] == 20
print("Configuracao definitiva verificada")
PY

# Controles experimentais.
for cpu in 0 1 2 3; do
    governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
    [[ "$governor" == performance ]] ||
        die "CPU$cpu esta em $governor, esperado performance"
done

[[ "$(vcgencmd get_throttled)" == "throttled=0x0" ]] ||
    die "Subtensao ou throttling detectado"

swapon --show | grep -q '/swapfile-cic17' ||
    die "Swap adicional nao esta ativo"

available_kb=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
(( available_kb >= 2 * 1024 * 1024 )) ||
    die "Menos de 2 GiB livres no armazenamento"

# Criar apenas os diretorios do novo dataset.
mkdir "$R" "$L" "$H"

cp "$0" "$H/runner_snapshot.sh"
cp "$CFG" "$H/config_snapshot.yaml"

{
    echo "dataset=$DS"
    echo "dataset_directory=$DATA"
    echo "config=$CFG"
    echo "config_sha256=$(sha256sum "$CFG" | cut -d' ' -f1)"
    echo "git_commit=$(git rev-parse HEAD)"
    echo "docker_image_id=$("${DOCKER[@]}" image inspect "$IMAGE" --format '{{.Id}}')"
    echo "started_utc=$(date -u +%FT%TZ)"
    for day in monday tuesday wednesday thursday friday; do
        sha256sum "$DATA/$day.csv"
    done
} > "$H/provenance.txt"

capture() {
    local phase="$1"
    {
        date -u --iso-8601=seconds
        uname -a
        lscpu
        free -h
        swapon --show
        df -h /
        uptime
        cat /proc/loadavg
        for cpu in 0 1 2 3; do
            printf 'cpu%s=' "$cpu"
            cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor"
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
    -e LATENCY_DATA_DIR=/data/raw
    -e LATENCY_OUTPUT_DIR=/artifact/results/cicids2017
    -v "$DATA:/data/raw:ro"
    -v "$ROOT/results:/artifact/results:rw"
)

stage() {
    local name="$1"
    say "$DS: $name"
    "${DOCKER[@]}" run "${ARGS[@]}" "${MOUNTS[@]}" \
        "$IMAGE" "$name" --config "$CFG" \
        2>&1 | tee "$L/$name.log"
}

capture before_prepare

stage prepare

[[ -s "$R/processed/dataset.npz" ]] ||
    die "Dataset processado ausente"

stage train

for model in LoR SGD NB DT RF GB AB MLP; do
    [[ -s "$R/models/$model.joblib" ]] ||
        die "Modelo ausente: $model"
done

say "Cooldown de 30 segundos"
sleep 30

quiet_host

[[ "$(vcgencmd get_throttled)" == "throttled=0x0" ]] ||
    die "Throttling antes do benchmark"

capture before_benchmark

monitor > "$H/benchmark_monitor.csv" &
MONITOR_PID=$!
taskset -pc 0 "$MONITOR_PID" \
    > "$H/monitor_affinity.txt" 2>&1 || true

stage benchmark

stop_monitor
capture after_benchmark

stage analyze

say "Validando resultados"

"${DOCKER[@]}" run --rm \
    --user "$(id -u):$(id -g)" \
    --network none --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=256m \
    -v "$R:/results:ro" \
    --entrypoint python "$IMAGE" -c '
import csv, glob, json
from pathlib import Path
import numpy as np

root = Path("/results")

with np.load(root / "processed/dataset.npz", allow_pickle=False) as data:
    features = data["X_train"].shape[1]
    assert features > 0

raw = sorted(glob.glob(str(root / "benchmark/raw/run_*.csv")))
assert len(raw) == 12, len(raw)

for filename in raw:
    with open(filename, newline="") as f:
        assert sum(1 for _ in csv.DictReader(f)) == 8640

with (root / "analysis/timing_summary.csv").open(newline="") as f:
    rows = list(csv.DictReader(f))

assert len(rows) == 288
assert {r["model"] for r in rows} == {
    "LoR", "SGD", "NB", "DT", "RF", "GB", "AB", "MLP"
}
assert {int(r["batch_size"]) for r in rows} == {
    1, 8, 16, 32, 64, 100
}
assert {float(r["requested_malicious_fraction"]) for r in rows} == {
    0, 0.01, 0.05, 0.1, 0.5, 1
}
assert {int(r["n"]) for r in rows} == {360}
assert {int(r["process_runs"]) for r in rows} == {12}

metadata = sorted(glob.glob(
    str(root / "benchmark/raw/metadata_*.json")
))
assert len(metadata) == 12

for filename in metadata:
    with open(filename) as f:
        m = json.load(f)
    assert m["one_cpu_affinity"] is True
    assert m["cpu_affinity"] == [3]
    assert all(
        int(p["num_threads"]) == 1
        for p in m["threadpool_info"]
    )

for name in (
    "training_metadata.json",
    "predictive_metrics.csv",
    "prediction_scores.npz"
):
    assert (root / name).is_file(), name

print("VALIDATION PASS")
print("Observacoes: 103680")
print("Configuracoes: 288")
print("Features:", features)
print("CPU: 3; threads: 1")
' 2>&1 | tee "$L/validation.log"

say "Analise de sensibilidade de limiar"

"${DOCKER[@]}" run --rm \
    --user "$(id -u):$(id -g)" \
    --network none --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=256m \
    -v "$R:/artifact/results/definitive:rw" \
    --entrypoint python "$IMAGE" \
    scripts/analyze_thresholds.py \
    /artifact/results/definitive/prediction_scores.npz \
    --output /artifact/results/definitive/analysis/threshold_sensitivity.csv \
    --seed 20260719 --max-samples 100000 \
    2>&1 | tee "$L/threshold_sensitivity.log"

[[ -s "$R/analysis/threshold_sensitivity.csv" ]] ||
    die "Analise de limiar ausente"

if awk -F, 'NR>1 && $7!="0x0" {bad=1} END {exit !bad}' \
    "$H/benchmark_monitor.csv"; then
    echo "AVISO: throttling registrado" | tee "$H/throttling_warning.txt"
fi

capture after

echo "completed_utc=$(date -u +%FT%TZ)" > "$H/completed.txt"

say "$DS FINALIZADO"
