#!/usr/bin/env python3
"""Select validation MCC thresholds and evaluate them on held-out test scores."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np


def binary_metrics(labels: np.ndarray, predictions: np.ndarray) -> dict[str, float]:
    benign = labels == 0
    malicious = labels == 1
    predicted_benign = ~predictions
    tn = int(np.sum(benign & predicted_benign))
    fp = int(np.sum(benign & predictions))
    fn = int(np.sum(malicious & predicted_benign))
    tp = int(np.sum(malicious & predictions))
    denominator = ((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn)) ** 0.5
    return {
        "precision": tp / (tp + fp) if tp + fp else 0.0,
        "recall": tp / (tp + fn) if tp + fn else 0.0,
        "mcc": (tp * tn - fp * fn) / denominator if denominator else 0.0,
        "false_positive_rate": fp / (fp + tn) if fp + tn else 0.0,
    }


def mcc_optimal_threshold(labels: np.ndarray, scores: np.ndarray) -> tuple[float, float]:
    """Return the score threshold with maximum MCC, using score >= threshold."""
    order = np.argsort(-scores, kind="stable")
    sorted_scores = scores[order]
    sorted_labels = labels[order]
    true_positive_cumulative = np.cumsum(sorted_labels == 1)
    false_positive_cumulative = np.cumsum(sorted_labels == 0)
    group_ends = np.r_[
        np.flatnonzero(sorted_scores[:-1] != sorted_scores[1:]),
        len(sorted_scores) - 1,
    ]
    tp = true_positive_cumulative[group_ends].astype(float)
    fp = false_positive_cumulative[group_ends].astype(float)
    positive = float(np.sum(labels == 1))
    negative = float(np.sum(labels == 0))
    fn = positive - tp
    tn = negative - fp
    denominator = np.sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn))
    mcc = np.divide(
        tp * tn - fp * fn,
        denominator,
        out=np.zeros_like(denominator),
        where=denominator != 0,
    )
    best = int(np.argmax(mcc))
    return float(sorted_scores[group_ends[best]]), float(mcc[best])


def prevalence_indices(
    labels: np.ndarray,
    malicious_fraction: float,
    max_samples: int,
    seed: int,
) -> np.ndarray:
    benign = np.flatnonzero(labels == 0)
    malicious = np.flatnonzero(labels == 1)
    feasible = min(
        max_samples,
        int(len(benign) / (1 - malicious_fraction)),
        int(len(malicious) / malicious_fraction),
    )
    malicious_count = max(1, int(round(feasible * malicious_fraction)))
    benign_count = min(len(benign), feasible - malicious_count)
    malicious_count = min(len(malicious), feasible - benign_count)
    rng = np.random.default_rng(seed)
    indices = np.concatenate(
        [
            rng.choice(benign, benign_count, replace=False),
            rng.choice(malicious, malicious_count, replace=False),
        ]
    )
    rng.shuffle(indices)
    return indices


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("scores", type=Path, help="prediction_scores.npz")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=20260719)
    parser.add_argument("--max-samples", type=int, default=100_000)
    args = parser.parse_args()
    fractions = (0.01, 0.05, 0.10, 0.50)
    rows: list[dict[str, float | str]] = []

    with np.load(args.scores) as exported:
        validation_labels = exported["y_validation"].astype(int)
        test_labels = exported["y_test"].astype(int)
        scenario_indices = {
            fraction: prevalence_indices(
                test_labels,
                fraction,
                args.max_samples,
                args.seed + index * 101,
            )
            for index, fraction in enumerate(fractions)
        }
        for model in exported["models"].tolist():
            validation_scores = exported[f"scores_{model}_validation"]
            test_scores = exported[f"scores_{model}_test"]
            threshold, validation_mcc = mcc_optimal_threshold(
                validation_labels, validation_scores
            )
            test = binary_metrics(test_labels, test_scores >= threshold)
            row: dict[str, float | str] = {
                "model": model,
                "validation_selected_threshold": threshold,
                "validation_mcc": validation_mcc,
                "balanced_test_mcc": test["mcc"],
                "balanced_test_recall": test["recall"],
                "balanced_test_false_positive_rate": test["false_positive_rate"],
            }
            for fraction, indices in scenario_indices.items():
                result = binary_metrics(
                    test_labels[indices], test_scores[indices] >= threshold
                )
                row[f"precision_at_{int(fraction * 100)}pct_malicious"] = result[
                    "precision"
                ]
            rows.append(row)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=list(rows[0]), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
