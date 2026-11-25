#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${TRADEOFF_DATA_DIR:-$(cd "$ROOT_DIR/.." && pwd)/datasets}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CIC17_URL="https://intrusion-detection.distrinet-research.be/CNS2022/Datasets/CICIDS2017_improved.zip"
ZENODO_BASE="https://zenodo.org/api/records/21435638/files"

CIC17_ZIP_SHA256="97fdb91d339e2d8cf5627f981b831e5e7e400b981c58181c451a38fd03c48883"
GENIDS_CIC17_SHA256="946c98e3562f2c7e2a1c6cea9d5d180db391a1b7390e76bb694b46f89bddf5b9"
GENIDS_CIC18_SHA256="b67bd1437ad1e4078296b7196946c4522390ed8f640ea1298f59b19b2923d7e2"
GENIDS_UNSW15_SHA256="2437a5fb6ae6f37d47e24e2fc4ee2df243248679f412a0f3dd1ffd7e757ddb1e"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

check_sha256() {
    local file="$1"
    local expected="$2"
    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
}

download() {
    local url="$1"
    local output="$2"
    echo "Downloading: $(basename "$output")"
    curl -L --fail --retry 3 --progress-bar -o "$output" "$url"
}

need_cmd curl
need_cmd unzip
need_cmd sha256sum

mkdir -p "$DATA_DIR/CICIDS2017"

echo "========================================"
echo " IDS TRADE-OFFs - Dataset Setup"
echo "========================================"
echo "Destination: $DATA_DIR"
echo

# ------------------------------------------------------------
# Improved CICIDS2017
# ------------------------------------------------------------
CIC17_ZIP="$DATA_DIR/CICIDS2017/CICIDS2017_improved.zip"

if [[ -f "$CIC17_ZIP" ]] && check_sha256 "$CIC17_ZIP" "$CIC17_ZIP_SHA256"; then
    echo "[OK] CICIDS2017_improved.zip"
else
    [[ -f "$CIC17_ZIP" ]] && {
        echo "ERROR: CICIDS2017_improved.zip exists, but its SHA-256 does not match." >&2
        exit 1
    }

    download "$CIC17_URL" "$TMP_DIR/CICIDS2017_improved.zip"

    check_sha256 "$TMP_DIR/CICIDS2017_improved.zip" "$CIC17_ZIP_SHA256" || {
        echo "ERROR: invalid SHA-256 for CICIDS2017_improved.zip" >&2
        exit 1
    }

    mv "$TMP_DIR/CICIDS2017_improved.zip" "$CIC17_ZIP"
    echo "[OK] CICIDS2017_improved.zip downloaded and verified"
fi

for day in monday tuesday wednesday thursday friday; do
    if [[ ! -f "$DATA_DIR/CICIDS2017/${day}.csv" ]]; then
        echo "Extracting ${day}.csv..."
        unzip -p "$CIC17_ZIP" "${day}.csv" > "$DATA_DIR/CICIDS2017/${day}.csv"
    fi
done

# ------------------------------------------------------------
# GenIDS helper
# ------------------------------------------------------------
install_genids() {
    local zip_name="$1"
    local member="$2"
    local output="$3"
    local expected_sha="$4"

    if [[ -f "$output" ]]; then
        if check_sha256 "$output" "$expected_sha"; then
            echo "[OK] $(basename "$output")"
            return
        fi

        echo "ERROR: $(basename "$output") exists, but its SHA-256 does not match." >&2
        exit 1
    fi

    local zip_path="$TMP_DIR/$zip_name"

    download "$ZENODO_BASE/$zip_name/content" "$zip_path"

    echo "Extracting $(basename "$output")..."
    unzip -p "$zip_path" "$member" > "$TMP_DIR/$(basename "$output")"

    check_sha256 "$TMP_DIR/$(basename "$output")" "$expected_sha" || {
        echo "ERROR: invalid SHA-256 for $(basename "$output")" >&2
        exit 1
    }

    mv "$TMP_DIR/$(basename "$output")" "$output"
    echo "[OK] $(basename "$output") downloaded and verified"
}

install_genids \
    "GenIDS-CIC17.zip" \
    "GenIDS-CIC17/GenIDS-CIC17.csv" \
    "$DATA_DIR/GenIDS-CIC17.csv" \
    "$GENIDS_CIC17_SHA256"

install_genids \
    "GenIDS-CIC18.zip" \
    "GenIDS-CIC18/GenIDS-CIC18.csv" \
    "$DATA_DIR/GenIDS-CIC18.csv" \
    "$GENIDS_CIC18_SHA256"

install_genids \
    "GenIDS-NB15.zip" \
    "GenIDS-NB15/GenIDS-UNSW15.csv" \
    "$DATA_DIR/GenIDS-UNSW15.csv" \
    "$GENIDS_UNSW15_SHA256"

echo
echo "========================================"
echo " ALL DATASETS ARE READY"
echo "========================================"
