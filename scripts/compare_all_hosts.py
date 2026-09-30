#!/usr/bin/env python3

"""
Compare complete multi-dataset executions from two physical hosts.

This wrapper applies the validated cross-host comparison independently
to each dataset produced by run_all_datasets_definitive.sh.

Expected run structure:

<run-root>/
    results/
        cicids2017/
        genids_cic17/
        genids_unsw15/
        genids_cic18/

Each dataset must contain:

    analysis/timing_summary.csv
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from compare_hosts import (
    compare_hosts,
    format_summary,
    load_summary,
)


DATASETS = [
    ("CICIDS2017", "cicids2017"),
    ("GenIDS-CIC17", "genids_cic17"),
    ("GenIDS-UNSW15", "genids_unsw15"),
    ("GenIDS-CIC18", "genids_cic18"),
]

EXPECTED_CONDITIONS = 288


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare two complete four-dataset latency-ids "
            "executions produced on independent hosts."
        )
    )

    parser.add_argument(
        "host_a_run",
        type=Path,
        help="Root directory of the complete Host-A run.",
    )

    parser.add_argument(
        "host_b_run",
        type=Path,
        help="Root directory of the complete Host-B run.",
    )

    parser.add_argument(
        "--host-a-name",
        default="Host-A",
        help="Display name for the first host.",
    )

    parser.add_argument(
        "--host-b-name",
        default="Host-B",
        help="Display name for the second host.",
    )

    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory for the complete cross-host comparison.",
    )

    return parser.parse_args()


def timing_summary_path(
    run_root: Path,
    dataset_dir: str,
) -> Path:
    return (
        run_root
        / "results"
        / dataset_dir
        / "analysis"
        / "timing_summary.csv"
    )


def main() -> None:
    args = parse_args()

    if not args.host_a_run.is_dir():
        raise FileNotFoundError(
            f"Host-A run root not found: {args.host_a_run}"
        )

    if not args.host_b_run.is_dir():
        raise FileNotFoundError(
            f"Host-B run root not found: {args.host_b_run}"
        )

    args.output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    aggregate_rows = []
    machine_summary = {
        "host_a_name": args.host_a_name,
        "host_b_name": args.host_b_name,
        "host_a_run": str(args.host_a_run.resolve()),
        "host_b_run": str(args.host_b_run.resolve()),
        "expected_conditions_per_dataset": EXPECTED_CONDITIONS,
        "datasets": {},
    }

    print("Complete cross-host comparison")
    print("==============================")
    print()
    print(f"Host A: {args.host_a_name}")
    print(f"Host B: {args.host_b_name}")
    print(f"Run A:  {args.host_a_run}")
    print(f"Run B:  {args.host_b_run}")

    for dataset_name, dataset_dir in DATASETS:
        print()
        print("=" * 72)
        print(dataset_name)
        print("=" * 72)

        path_a = timing_summary_path(
            args.host_a_run,
            dataset_dir,
        )

        path_b = timing_summary_path(
            args.host_b_run,
            dataset_dir,
        )

        print(f"Host A summary: {path_a}")
        print(f"Host B summary: {path_b}")

        a = load_summary(
            path_a,
            args.host_a_name,
        )

        b = load_summary(
            path_b,
            args.host_b_name,
        )

        summary, details, per_model = compare_hosts(
            a,
            b,
            args.host_a_name,
            args.host_b_name,
            EXPECTED_CONDITIONS,
        )

        dataset_output = (
            args.output_dir / dataset_dir
        )

        dataset_output.mkdir(
            parents=True,
            exist_ok=True,
        )

        text = format_summary(
            summary,
            args.host_a_name,
            args.host_b_name,
        )

        print()
        print(text)

        details.to_csv(
            dataset_output / "matched_conditions.csv",
            index=False,
        )

        per_model.to_csv(
            dataset_output / "per_model_spearman.csv",
            index=False,
        )

        (
            dataset_output / "cross_host_summary.txt"
        ).write_text(
            text + "\n",
            encoding="utf-8",
        )

        row = {
            "dataset": dataset_name,
            **summary,
        }

        aggregate_rows.append(row)

        machine_summary["datasets"][dataset_dir] = {
            "dataset_name": dataset_name,
            **summary,
        }

        print()
        print(f"PASS: {dataset_name}")

    aggregate = pd.DataFrame(aggregate_rows)

    aggregate.to_csv(
        args.output_dir / "cross_host_all_datasets.csv",
        index=False,
    )

    (
        args.output_dir / "cross_host_all_datasets.json"
    ).write_text(
        json.dumps(
            machine_summary,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print()
    print("=" * 72)
    print("ALL DATASETS")
    print("=" * 72)
    print()
    print(aggregate.to_string(index=False))

    print()
    print(
        "Total matched conditions: "
        f"{aggregate['matched_conditions'].sum()}"
    )

    expected_total = (
        EXPECTED_CONDITIONS * len(DATASETS)
    )

    actual_total = int(
        aggregate["matched_conditions"].sum()
    )

    if actual_total != expected_total:
        raise RuntimeError(
            "Unexpected total number of matched conditions: "
            f"expected {expected_total}, "
            f"got {actual_total}"
        )

    print(
        "PASS: all four datasets contain "
        f"{EXPECTED_CONDITIONS} matched conditions"
    )

    print()
    print(
        "Outputs written to: "
        f"{args.output_dir}"
    )

    print()
    print(
        "COMPLETE FOUR-DATASET CROSS-HOST "
        "COMPARISON: PASS"
    )


if __name__ == "__main__":
    main()
