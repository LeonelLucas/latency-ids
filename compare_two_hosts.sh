#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd -P
)"

COMPARE_SCRIPT="$SCRIPT_DIR/scripts/compare_all_hosts.py"

usage() {
    cat <<'EOF'
Usage:
  ./compare_two_hosts.sh HOST_A_RUN HOST_B_RUN [OUTPUT_DIR]

Arguments:
  HOST_A_RUN   Complete run directory produced on the first host.
  HOST_B_RUN   Complete run directory produced on the second host.
  OUTPUT_DIR   Optional output directory for the cross-host analysis.

Example:
  ./compare_two_hosts.sh \
      /path/to/host-a/multidataset-run-... \
      /path/to/host-b/multidataset-run-... \
      ./cross-host-analysis
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

[[ $# -ge 2 && $# -le 3 ]] || {
    usage >&2
    exit 2
}

HOST_A_RUN="$(realpath "$1")"
HOST_B_RUN="$(realpath "$2")"

if [[ $# -eq 3 ]]; then
    OUTPUT_DIR="$(realpath -m "$3")"
else
    STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    OUTPUT_DIR="$PWD/cross-host-analysis-$STAMP"
fi

[[ -d "$HOST_A_RUN" ]] ||
    die "Host A run directory not found: $HOST_A_RUN"

[[ -d "$HOST_B_RUN" ]] ||
    die "Host B run directory not found: $HOST_B_RUN"

[[ -f "$COMPARE_SCRIPT" ]] ||
    die "Comparison script not found: $COMPARE_SCRIPT"

DATASETS=(
    cicids2017
    genids_cic17
    genids_unsw15
    genids_cic18
)

echo "========================================"
echo " IDS TRADE-OFFs - Cross-Host Analysis"
echo "========================================"
echo
echo "Host A: $HOST_A_RUN"
echo "Host B: $HOST_B_RUN"
echo "Output: $OUTPUT_DIR"
echo

echo "Checking complete host executions..."

for dataset in "${DATASETS[@]}"; do
    A_SUMMARY="$HOST_A_RUN/results/$dataset/analysis/timing_summary.csv"
    B_SUMMARY="$HOST_B_RUN/results/$dataset/analysis/timing_summary.csv"

    [[ -s "$A_SUMMARY" ]] ||
        die "Host A is missing $dataset timing summary."

    [[ -s "$B_SUMMARY" ]] ||
        die "Host B is missing $dataset timing summary."

    printf '  PASS: %-15s\n' "$dataset"
done

echo
echo "Running post-hoc cross-host analysis..."

mkdir -p "$OUTPUT_DIR"

python3 "$COMPARE_SCRIPT" \
    "$HOST_A_RUN" \
    "$HOST_B_RUN" \
    --host-a-name "Host-A" \
    --host-b-name "Host-B" \
    --output-dir "$OUTPUT_DIR"

echo
echo "========================================"
echo " CROSS-HOST ANALYSIS COMPLETE"
echo "========================================"
echo "Results: $OUTPUT_DIR"
