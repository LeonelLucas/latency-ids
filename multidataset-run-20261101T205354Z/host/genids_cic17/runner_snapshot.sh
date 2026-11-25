#!/usr/bin/env bash
set -Eeuo pipefail
source /home/lucasleonel/latency-ids/runners/raspberry/common_genids.sh

run_dataset \
    genids_cic17 \
    946c98e3562f2c7e2a1c6cea9d5d180db391a1b7390e76bb694b46f89bddf5b9 \
    GenIDS-CIC17.csv \
    genids_cic17
