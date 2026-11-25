#!/usr/bin/env python3

"""
Cross-host comparison for latency-ids.

The primary comparison reproduces the procedure used in the original
two-host experiment:

- match conditions by model, batch size, and requested malicious fraction;
- compare median_us_per_flow;
- compute Spearman rank correlation across matched conditions;
- summarize the median Host-B / Host-A latency ratio.

The script is intentionally independent from the experiment runner.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr


KEYS = [
    "model",
    "batch_size",
    "requested_malicious_fraction",
]

METRIC = "median_us_per_flow"

REQUIRED_COLUMNS = KEYS + [METRIC]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare matched timing-summary conditions from two "
            "independent host executions."
        )
    )

    parser.add_argument(
        "host_a",
        type=Path,
        help="Path to Host-A timing_summary.csv",
    )

    parser.add_argument(
        "host_b",
        type=Path,
        help="Path to Host-B timing_summary.csv",
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
        default=None,
        help=(
            "Optional directory in which detailed comparison CSV files "
            "and the text summary are written."
        ),
    )

    parser.add_argument(
        "--expected-conditions",
        type=int,
        default=None,
        help=(
            "Require exactly this number of matched conditions. "
            "Use 288 for one definitive dataset."
        ),
    )

    return parser.parse_args()


def load_summary(path: Path, name: str) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(
            f"{name}: timing summary not found: {path}"
        )

    df = pd.read_csv(path)

    missing = [
        column
        for column in REQUIRED_COLUMNS
        if column not in df.columns
    ]

    if missing:
        raise ValueError(
            f"{name}: missing required columns: {missing}"
        )

    if df.empty:
        raise ValueError(f"{name}: timing summary is empty")

    if df.duplicated(KEYS).any():
        duplicated = df.loc[
            df.duplicated(KEYS, keep=False),
            KEYS,
        ]

        raise ValueError(
            f"{name}: duplicate experimental conditions detected:\n"
            f"{duplicated.to_string(index=False)}"
        )

    values = pd.to_numeric(df[METRIC], errors="coerce")

    if values.isna().any():
        raise ValueError(
            f"{name}: {METRIC} contains missing/non-numeric values"
        )

    if not np.isfinite(values.to_numpy(dtype=float)).all():
        raise ValueError(
            f"{name}: {METRIC} contains non-finite values"
        )

    if (values <= 0).any():
        raise ValueError(
            f"{name}: {METRIC} must contain only positive values"
        )

    return df[REQUIRED_COLUMNS].copy()


def compare_hosts(
    a: pd.DataFrame,
    b: pd.DataFrame,
    host_a_name: str,
    host_b_name: str,
    expected_conditions: int | None,
):
    merged = a.merge(
        b,
        on=KEYS,
        how="inner",
        suffixes=("_a", "_b"),
        validate="one_to_one",
    )

    if len(merged) != len(a) or len(merged) != len(b):
        raise ValueError(
            "The two timing summaries do not contain exactly the same "
            "experimental conditions. "
            f"{host_a_name}={len(a)}, "
            f"{host_b_name}={len(b)}, "
            f"matched={len(merged)}."
        )

    if expected_conditions is not None:
        if len(merged) != expected_conditions:
            raise ValueError(
                "Unexpected number of matched conditions: "
                f"expected {expected_conditions}, got {len(merged)}"
            )

    x = merged[f"{METRIC}_a"].to_numpy(dtype=float)
    y = merged[f"{METRIC}_b"].to_numpy(dtype=float)

    rho, p_value = spearmanr(x, y)

    if not np.isfinite(rho):
        raise ValueError(
            "Spearman correlation could not be computed."
        )

    ratio_b_a = y / x
    ratio_a_b = x / y

    symmetric_pct_difference = (
        np.abs(x - y)
        / ((np.abs(x) + np.abs(y)) / 2.0)
        * 100.0
    )

    details = merged[KEYS].copy()

    details[f"{host_a_name}_median_us_per_flow"] = x
    details[f"{host_b_name}_median_us_per_flow"] = y
    details[f"{host_b_name}_over_{host_a_name}"] = ratio_b_a
    details[f"{host_a_name}_over_{host_b_name}"] = ratio_a_b
    details["symmetric_abs_pct_difference"] = (
        symmetric_pct_difference
    )

    per_model_rows = []

    for model in sorted(merged["model"].unique()):
        subset = merged.loc[merged["model"] == model]

        model_a = subset[f"{METRIC}_a"].to_numpy(dtype=float)
        model_b = subset[f"{METRIC}_b"].to_numpy(dtype=float)

        model_rho, model_p = spearmanr(model_a, model_b)

        per_model_rows.append(
            {
                "model": model,
                "n_conditions": len(subset),
                "spearman_rho": model_rho,
                "spearman_p": model_p,
                f"median_{host_b_name}_over_{host_a_name}": (
                    np.median(model_b / model_a)
                ),
            }
        )

    per_model = pd.DataFrame(per_model_rows)

    summary = {
        "matched_conditions": len(merged),
        "spearman_rho": float(rho),
        "spearman_p": float(p_value),
        f"median_{host_b_name}_over_{host_a_name}": float(
            np.median(ratio_b_a)
        ),
        f"median_{host_a_name}_over_{host_b_name}": float(
            np.median(ratio_a_b)
        ),
        "median_symmetric_abs_pct_difference": float(
            np.median(symmetric_pct_difference)
        ),
    }

    return summary, details, per_model


def format_summary(
    summary: dict,
    host_a_name: str,
    host_b_name: str,
) -> str:
    p_value = summary["spearman_p"]

    if p_value < 0.001:
        p_text = "< 0.001"
    else:
        p_text = f"= {p_value:.6g}"

    lines = [
        "Cross-host comparison",
        "=====================",
        "",
        f"Host A: {host_a_name}",
        f"Host B: {host_b_name}",
        "",
        (
            "Matched conditions: "
            f"{summary['matched_conditions']}"
        ),
        "",
        "Primary cross-host statistic:",
        (
            "  Spearman rho: "
            f"{summary['spearman_rho']:.10f}"
        ),
        f"  p-value:      {p_text}",
        "",
        "Median latency ratios:",
        (
            f"  {host_b_name} / {host_a_name}: "
            f"{summary[f'median_{host_b_name}_over_{host_a_name}']:.10f}"
        ),
        (
            f"  {host_a_name} / {host_b_name}: "
            f"{summary[f'median_{host_a_name}_over_{host_b_name}']:.10f}"
        ),
        "",
        "Supplementary descriptive statistic:",
        (
            "  Median symmetric absolute percentage difference: "
            f"{summary['median_symmetric_abs_pct_difference']:.10f}%"
        ),
    ]

    return "\n".join(lines)


def main() -> None:
    args = parse_args()

    a = load_summary(args.host_a, args.host_a_name)
    b = load_summary(args.host_b, args.host_b_name)

    summary, details, per_model = compare_hosts(
        a,
        b,
        args.host_a_name,
        args.host_b_name,
        args.expected_conditions,
    )

    text = format_summary(
        summary,
        args.host_a_name,
        args.host_b_name,
    )

    print(text)

    print()
    print("Per-model Spearman")
    print("==================")
    print(per_model.to_string(index=False))

    if args.output_dir is not None:
        args.output_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

        details.to_csv(
            args.output_dir / "matched_conditions.csv",
            index=False,
        )

        per_model.to_csv(
            args.output_dir / "per_model_spearman.csv",
            index=False,
        )

        (
            args.output_dir / "cross_host_summary.txt"
        ).write_text(
            text + "\n",
            encoding="utf-8",
        )

        print()
        print(
            "Outputs written to: "
            f"{args.output_dir}"
        )


if __name__ == "__main__":
    main()
