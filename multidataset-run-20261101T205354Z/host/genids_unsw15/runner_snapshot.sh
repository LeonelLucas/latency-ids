#!/usr/bin/env bash
set -Eeuo pipefail
source /home/lucasleonel/latency-ids/runners/raspberry/common_genids.sh

run_dataset \
    genids_unsw15 \
    2437a5fb6ae6f37d47e24e2fc4ee2df243248679f412a0f3dd1ffd7e757ddb1e \
    GenIDS-UNSW15.csv \
    genids_unsw15
