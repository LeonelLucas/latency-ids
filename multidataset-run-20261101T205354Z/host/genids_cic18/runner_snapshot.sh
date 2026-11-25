#!/usr/bin/env bash
set -Eeuo pipefail

source /home/lucasleonel/latency-ids/runners/raspberry/common_genids.sh

run_dataset \
    genids_cic18 \
    7676a4b04dba4ddc9e5c7fcc532e6c72b915251e3c88c5f055f82b185f9b907a \
    GenIDS-CIC18-subset-v2.csv \
    genids_cic18
