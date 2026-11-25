
#!/usr/bin/env python3
"""Prepare GenIDS-CIC17 for the original latency-ids pipeline.

The adapter preserves the dataset.npz contract and the two-stage sampling
strategy used by latency_artifact.pipeline.prepare, while reading the single
GenIDS CSV in chunks.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from latency_artifact.pipeline import (
    _sample_indices,
    load_config,
    sha256,
    write_json,
)


def _normalize_dates(series: pd.Series) -> pd.Series:
    """Convert GenIDS DD/MM/YYYY dates to ISO YYYY-MM-DD."""
    parsed = pd.to_datetime(
        series,
        format="%d/%m/%Y",
        errors="coerce",
    )
    return parsed.dt.strftime("%Y-%m-%d")


def _validate_configuration(
    config: dict[str, Any],
    csv_path: Path,
) -> list[str]:
    """Validate CSV schema and return the ordered predictive feature list."""

    header = pd.read_csv(csv_path, nrows=0)

    split_mode = config["data"].get(
        "split_mode",
        "days",
    )

    label_column = config["genids"]["label_column"]
    excluded = list(config["genids"]["exclude_columns"])

    if split_mode == "days":
        required = [
            config["genids"]["date_column"],
            label_column,
        ]
    elif split_mode == "temporal_percentage":
        required = [
            config["data"]["temporal"]["order_column"],
            label_column,
        ]
    else:
        raise ValueError(
            f"Unsupported split_mode: {split_mode}"
        )
    missing_required = [
        column
        for column in required
        if column not in header.columns
    ]

    if missing_required:
        raise ValueError(
            f"Missing required columns: {missing_required}"
        )

    missing_excluded = [
        column
        for column in excluded
        if column not in header.columns
    ]

    if missing_excluded:
        raise ValueError(
            "Configured exclusion columns not found: "
            f"{missing_excluded}"
        )

    excluded_set = set(excluded)

    features = [
        column
        for column in header.columns
        if column not in excluded_set
    ]

    expected = config["genids"].get(
        "expected_feature_count"
    )

    if expected is not None and len(features) != int(expected):
        raise ValueError(
            f"Expected {expected} features, found {len(features)}"
        )

    return features


def _collect_daily_candidates(
    config: dict[str, Any],
    csv_path: Path,
    features: list[str],
) -> tuple[
    dict[str, dict[int, list[np.ndarray]]],
    dict[str, dict[str, Any]],
]:
    """Read the source CSV once and collect finite rows by date and class."""

    date_column = config["genids"]["date_column"]
    label_column = config["genids"]["label_column"]

    benign_label = str(
        config["genids"]["benign_label"]
    ).strip().lower()

    malicious_label = str(
        config["genids"]["malicious_label"]
    ).strip().lower()

    chunksize = int(
        config["genids"].get("chunksize", 100_000)
    )

    split_names = ("train", "validation", "test")

    configured_days: list[str] = []

    for split_name in split_names:
        configured_days.extend(
            str(day)
            for day in config["data"]["splits"][split_name]["days"]
        )

    if len(configured_days) != len(set(configured_days)):
        raise ValueError(
            "A date appears in more than one temporal split."
        )

    day_set = set(configured_days)

    daily_parts: dict[
        str,
        dict[int, list[np.ndarray]],
    ] = {
        day: {0: [], 1: []}
        for day in configured_days
    }

    daily_manifest: dict[str, dict[str, Any]] = {
        day: {
            "rows": 0,
            "finite_rows": 0,
            "effective_benign": 0,
            "effective_malicious": 0,
        }
        for day in configured_days
    }

    usecols = features + [date_column, label_column]

    print(
        f"Reading {csv_path} in chunks of {chunksize:,} rows..."
    )

    rows_read = 0

    for chunk_number, chunk in enumerate(
        pd.read_csv(
            csv_path,
            usecols=usecols,
            chunksize=chunksize,
            low_memory=False,
        ),
        start=1,
    ):
        rows_read += len(chunk)

        normalized_dates = _normalize_dates(
            chunk[date_column]
        )

        relevant = normalized_dates.isin(day_set)

        if relevant.any():
            frame = chunk.loc[relevant].copy()
            frame["_adapter_date"] = normalized_dates.loc[
                relevant
            ].to_numpy()

            raw_labels = (
                frame[label_column]
                .astype(str)
                .str.strip()
                .str.lower()
            )

            valid_labels = raw_labels.isin(
                [benign_label, malicious_label]
            )

            if not valid_labels.all():
                unexpected = sorted(
                    raw_labels.loc[~valid_labels]
                    .unique()
                    .tolist()
                )
                raise ValueError(
                    "Unexpected binary labels found: "
                    f"{unexpected}"
                )

            labels = (
                raw_labels.eq(malicious_label)
                .to_numpy(dtype=np.int8)
            )

            values = frame[features].to_numpy(
                dtype=np.float64,
                copy=False,
            )

            dates = frame["_adapter_date"].to_numpy()

            finite = np.isfinite(values).all(axis=1)

            for day in configured_days:
                day_mask = dates == day

                if not day_mask.any():
                    continue

                manifest = daily_manifest[day]

                manifest["rows"] += int(day_mask.sum())

                day_finite = day_mask & finite

                manifest["finite_rows"] += int(
                    day_finite.sum()
                )

                if not day_finite.any():
                    continue

                day_values = values[day_finite]
                day_labels = labels[day_finite]

                benign_count = int(
                    (day_labels == 0).sum()
                )
                malicious_count = int(
                    (day_labels == 1).sum()
                )

                manifest["effective_benign"] += benign_count
                manifest["effective_malicious"] += malicious_count

                for class_id in (0, 1):
                    class_mask = day_labels == class_id

                    if class_mask.any():
                        daily_parts[day][class_id].append(
                            np.asarray(
                                day_values[class_mask],
                                dtype=np.float64,
                            )
                        )

        if chunk_number % 10 == 0:
            print(
                f"  chunks={chunk_number:,} "
                f"rows={rows_read:,}"
            )

    print(f"Finished reading {rows_read:,} rows.")

    return daily_parts, daily_manifest


def _build_split(
    split_name: str,
    spec: dict[str, Any],
    split_seed: int,
    daily_parts: dict[
        str,
        dict[int, list[np.ndarray]],
    ],
    daily_manifest: dict[str, dict[str, Any]],
) -> tuple[
    np.ndarray,
    np.ndarray,
    dict[str, Any],
]:
    """Apply the original per-day and split-level sampling strategy."""

    days = [str(day) for day in spec["days"]]
    max_per_class = int(spec["max_per_class"])

    rng = np.random.default_rng(split_seed)

    class_parts: dict[int, list[np.ndarray]] = {
        0: [],
        1: [],
    }

    split_day_manifest: dict[str, Any] = {}

    for day_index, day in enumerate(days):
        split_day_manifest[day] = daily_manifest[day]

        for class_id in (0, 1):
            parts = daily_parts[day][class_id]

            if not parts:
                continue

            candidates = np.concatenate(
                parts,
                axis=0,
            )

            day_rng = np.random.default_rng(
                split_seed
                + day_index * 17
                + class_id
            )

            selected = _sample_indices(
                np.arange(len(candidates)),
                max_per_class,
                day_rng,
            )

            if len(selected):
                class_parts[class_id].append(
                    np.asarray(
                        candidates[selected],
                        dtype=np.float64,
                    )
                )

    selected_parts: list[np.ndarray] = []
    selected_labels: list[np.ndarray] = []

    for class_id in (0, 1):
        if not class_parts[class_id]:
            raise ValueError(
                f"No class {class_id} records in "
                f"{split_name} days {days}"
            )

        candidates = np.concatenate(
            class_parts[class_id],
            axis=0,
        )

        indices = _sample_indices(
            np.arange(len(candidates)),
            max_per_class,
            rng,
        )

        selected_parts.append(
            candidates[indices]
        )

        selected_labels.append(
            np.full(
                len(indices),
                class_id,
                dtype=np.int8,
            )
        )

    x = np.concatenate(
        selected_parts,
        axis=0,
    )

    y = np.concatenate(
        selected_labels,
        axis=0,
    )

    order = rng.permutation(len(y))

    return (
        x[order],
        y[order],
        split_day_manifest,
    )



def _build_temporal_split(
    split_name: str,
    values: np.ndarray,
    labels: np.ndarray,
    max_per_class: int,
    split_seed: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Apply the original split-level class sampling strategy."""

    rng = np.random.default_rng(split_seed)

    selected_parts: list[np.ndarray] = []
    selected_labels: list[np.ndarray] = []

    for class_id in (0, 1):
        candidates = values[labels == class_id]

        if not len(candidates):
            raise ValueError(
                f"No class {class_id} records in "
                f"{split_name} temporal interval"
            )

        indices = _sample_indices(
            np.arange(len(candidates)),
            max_per_class,
            rng,
        )

        selected_parts.append(
            candidates[indices]
        )

        selected_labels.append(
            np.full(
                len(indices),
                class_id,
                dtype=np.int8,
            )
        )

    x = np.concatenate(
        selected_parts,
        axis=0,
    )

    y = np.concatenate(
        selected_labels,
        axis=0,
    )

    order = rng.permutation(len(y))

    return x[order], y[order]


def _collect_temporal_candidates(
    config: dict[str, Any],
    csv_path: Path,
    features: list[str],
) -> tuple[
    dict[str, tuple[np.ndarray, np.ndarray]],
    dict[str, dict[str, Any]],
]:
    """Collect chronologically ordered percentage-based temporal splits."""

    temporal = config["data"]["temporal"]
    order_column = str(temporal["order_column"])
    label_column = config["genids"]["label_column"]

    benign_label = str(
        config["genids"]["benign_label"]
    ).strip().lower()

    malicious_label = str(
        config["genids"]["malicious_label"]
    ).strip().lower()

    chunksize = int(
        config["genids"].get("chunksize", 100_000)
    )

    train_end = float(temporal["train_end"])
    validation_end = float(temporal["validation_end"])

    if not 0.0 < train_end < validation_end < 1.0:
        raise ValueError(
            "Temporal boundaries must satisfy "
            "0 < train_end < validation_end < 1."
        )

    print(
        f"Reading temporal order column: {order_column}"
    )

    order_parts: list[np.ndarray] = []

    for chunk in pd.read_csv(
        csv_path,
        usecols=[order_column],
        chunksize=chunksize,
        low_memory=False,
    ):
        order_parts.append(
            chunk[order_column].to_numpy(
                dtype=np.float64,
                copy=False,
            )
        )

    order_values = np.concatenate(order_parts)

    if not np.isfinite(order_values).all():
        raise ValueError(
            f"Non-finite values found in {order_column}."
        )

    row_order = np.argsort(
        order_values,
        kind="stable",
    )

    total_rows = len(row_order)
    train_stop = int(total_rows * train_end)
    validation_stop = int(
        total_rows * validation_end
    )

    chronological_position = np.empty(
        total_rows,
        dtype=np.int64,
    )
    chronological_position[row_order] = np.arange(
        total_rows,
        dtype=np.int64,
    )

    split_parts: dict[
        str,
        dict[str, list[np.ndarray]],
    ] = {
        "train": {"values": [], "labels": []},
        "validation": {"values": [], "labels": []},
        "test": {"values": [], "labels": []},
    }

    split_manifest: dict[str, dict[str, Any]] = {
        "train": {
            "start_index": 0,
            "stop_index": train_stop,
        },
        "validation": {
            "start_index": train_stop,
            "stop_index": validation_stop,
        },
        "test": {
            "start_index": validation_stop,
            "stop_index": total_rows,
        },
    }

    for manifest in split_manifest.values():
        manifest["rows"] = 0
        manifest["finite_rows"] = 0
        manifest["effective_benign"] = 0
        manifest["effective_malicious"] = 0

    usecols = list(
        dict.fromkeys(
            features + [label_column]
        )
    )

    rows_read = 0

    print(
        f"Reading {csv_path} in chunks of "
        f"{chunksize:,} rows..."
    )

    for chunk_number, chunk in enumerate(
        pd.read_csv(
            csv_path,
            usecols=usecols,
            chunksize=chunksize,
            low_memory=False,
        ),
        start=1,
    ):
        start = rows_read
        stop = start + len(chunk)

        positions = chronological_position[start:stop]
        rows_read = stop

        raw_labels = (
            chunk[label_column]
            .astype(str)
            .str.strip()
            .str.lower()
        )

        valid_labels = raw_labels.isin(
            [benign_label, malicious_label]
        )

        if not valid_labels.all():
            unexpected = sorted(
                raw_labels.loc[~valid_labels]
                .unique()
                .tolist()
            )
            raise ValueError(
                "Unexpected binary labels found: "
                f"{unexpected}"
            )

        labels = (
            raw_labels.eq(malicious_label)
            .to_numpy(dtype=np.int8)
        )

        values = chunk[features].to_numpy(
            dtype=np.float64,
            copy=False,
        )

        finite = np.isfinite(values).all(axis=1)

        masks = {
            "train": positions < train_stop,
            "validation": (
                (positions >= train_stop)
                & (positions < validation_stop)
            ),
            "test": positions >= validation_stop,
        }

        for split_name, split_mask in masks.items():
            manifest = split_manifest[split_name]

            manifest["rows"] += int(
                split_mask.sum()
            )

            split_finite = split_mask & finite

            manifest["finite_rows"] += int(
                split_finite.sum()
            )

            if not split_finite.any():
                continue

            split_values = values[split_finite]
            split_labels = labels[split_finite]

            manifest["effective_benign"] += int(
                (split_labels == 0).sum()
            )
            manifest["effective_malicious"] += int(
                (split_labels == 1).sum()
            )

            split_parts[split_name]["values"].append(
                np.asarray(
                    split_values,
                    dtype=np.float64,
                )
            )
            split_parts[split_name]["labels"].append(
                np.asarray(
                    split_labels,
                    dtype=np.int8,
                )
            )

        if chunk_number % 10 == 0:
            print(
                f"  chunks={chunk_number:,} "
                f"rows={rows_read:,}"
            )

    if rows_read != total_rows:
        raise ValueError(
            "Row count changed between temporal passes."
        )

    collected: dict[
        str,
        tuple[np.ndarray, np.ndarray],
    ] = {}

    for split_name in (
        "train",
        "validation",
        "test",
    ):
        value_parts = split_parts[split_name]["values"]
        label_parts = split_parts[split_name]["labels"]

        if not value_parts:
            raise ValueError(
                f"No finite rows in {split_name}."
            )

        collected[split_name] = (
            np.concatenate(value_parts, axis=0),
            np.concatenate(label_parts, axis=0),
        )

    return collected, split_manifest


def prepare_genids(config: dict[str, Any]) -> None:
    """Prepare a GenIDS dataset using the original artifact contract."""

    csv_path = Path(config["paths"]["data_file"])
    output_root = Path(config["paths"]["output_dir"])

    if not csv_path.exists():
        raise FileNotFoundError(
            f"GenIDS dataset not found: {csv_path}"
        )

    processed = output_root / "processed"

    processed.mkdir(
        parents=True,
        exist_ok=True,
    )

    destination = processed / "dataset.npz"

    if destination.exists():
        raise FileExistsError(
            f"Prepared dataset already exists: {destination}"
        )

    seed = int(config["seed"])

    features = _validate_configuration(
        config,
        csv_path,
    )

    split_mode = config["data"].get(
        "split_mode",
        "days",
    )

    print(f"Dataset: {csv_path}")
    print(f"Feature count: {len(features)}")
    print(f"Split mode: {split_mode}")

    if split_mode == "days":
        print("Temporal split:")

        for split_name in (
            "train",
            "validation",
            "test",
        ):
            print(
                f"  {split_name}: "
                f"{config['data']['splits'][split_name]['days']}"
            )

        daily_parts, daily_manifest = (
            _collect_daily_candidates(
                config=config,
                csv_path=csv_path,
                features=features,
            )
        )

        temporal_data = None
        temporal_manifest = None

    elif split_mode == "temporal_percentage":
        temporal = config["data"]["temporal"]

        print(
            "Temporal percentage split: "
            f"train=0-{float(temporal['train_end']):.2%}, "
            f"validation="
            f"{float(temporal['train_end']):.2%}-"
            f"{float(temporal['validation_end']):.2%}, "
            f"test="
            f"{float(temporal['validation_end']):.2%}-100%"
        )

        temporal_data, temporal_manifest = (
            _collect_temporal_candidates(
                config=config,
                csv_path=csv_path,
                features=features,
            )
        )

        daily_parts = None
        daily_manifest = None

    else:
        raise ValueError(
            f"Unsupported split_mode: {split_mode}"
        )

    arrays: dict[str, np.ndarray] = {}

    manifest: dict[str, Any] = {
        "seed": seed,
        "dataset": config["genids"].get(
            "name",
            "GenIDS",
        ),
        "source_file": str(csv_path.resolve()),
        "source_sha256": sha256(csv_path),
        "split_mode": split_mode,
        "splits": {},
        "features": features,
        "excluded_columns": list(
            config["genids"]["exclude_columns"]
        ),
    }

    if split_mode == "temporal_percentage":
        manifest["temporal_split"] = {
            "order_column": config["data"]["temporal"]["order_column"],
            "sort_kind": "stable",
            "train_end": float(
                config["data"]["temporal"]["train_end"]
            ),
            "validation_end": float(
                config["data"]["temporal"]["validation_end"]
            ),
        }

    for split_index, split_name in enumerate(
        ("train", "validation", "test")
    ):
        spec = config["data"]["splits"][split_name]

        split_seed = (
            seed
            + split_index * 10_000
        )

        if split_mode == "days":
            x, y, day_manifest = _build_split(
                split_name=split_name,
                spec=spec,
                split_seed=split_seed,
                daily_parts=daily_parts,
                daily_manifest=daily_manifest,
            )

            split_manifest = {
                "days": day_manifest,
            }

        else:
            values, labels = temporal_data[split_name]

            x, y = _build_temporal_split(
                split_name=split_name,
                values=values,
                labels=labels,
                max_per_class=int(spec["max_per_class"]),
                split_seed=split_seed,
            )

            split_manifest = dict(
                temporal_manifest[split_name]
            )

        arrays[f"X_{split_name}"] = x
        arrays[f"y_{split_name}"] = y

        split_manifest.update({
            "selected_rows": int(len(y)),
            "selected_benign": int(
                (y == 0).sum()
            ),
            "selected_malicious": int(
                (y == 1).sum()
            ),
        })

        manifest["splits"][split_name] = split_manifest

        print(
            f"{split_name}: X={x.shape} "
            f"benign={int((y == 0).sum()):,} "
            f"malicious={int((y == 1).sum()):,}"
        )

    arrays["feature_names"] = np.asarray(
        features,
        dtype=str,
    )

    np.savez_compressed(
        destination,
        **arrays,
    )

    write_json(
        processed / "dataset_manifest.json",
        manifest,
    )

    print()
    print("GenIDS preparation completed.")
    print(f"Dataset: {destination}")
    print(
        "Manifest: "
        f"{processed / 'dataset_manifest.json'}"
    )
    print(f"Features: {len(features)}")


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--config",
        required=True,
        type=Path,
    )

    args = parser.parse_args()

    config = load_config(args.config)

    prepare_genids(config)


if __name__ == "__main__":
    main()


