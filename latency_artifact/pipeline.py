#!/usr/bin/env python3
"""End-to-end data, training, timing, and analysis pipeline.

The benchmark deliberately uses sequential independent processes. Parallel
workers would increase throughput of the experiment itself but contaminate the
latency observations through resource contention.
"""

from __future__ import annotations

import argparse
import gc
import hashlib
import itertools
import json
import multiprocessing as mp
import os
import platform
import random
import sys
import time
import warnings
from pathlib import Path
from typing import Any

import joblib
import matplotlib
import numpy as np
import pandas as pd
import scipy
import sklearn
import yaml
from matplotlib import pyplot as plt
from scipy import stats
from sklearn.base import clone
from sklearn.ensemble import AdaBoostClassifier, GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression, SGDClassifier
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    matthews_corrcoef,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.naive_bayes import GaussianNB
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier
from threadpoolctl import threadpool_info, threadpool_limits

matplotlib.use("Agg")

DROP_COLUMNS = [
    "Src IP",
    "Dst IP",
    "id",
    "Flow ID",
    "Timestamp",
    "Label",
    # Dataset annotation, unavailable to a deployed detector and therefore a
    # source of target leakage if retained as a predictor.
    "Attempted Category",
]
REQUIRED_META_COLUMNS = ["Label", "Attempted Category"]


def load_config(path: Path) -> dict[str, Any]:
    raw = os.path.expandvars(path.read_text(encoding="utf-8"))
    if "${" in raw:
        raise ValueError(
            "Unresolved environment variable in config. Set LATENCY_DATA_DIR "
            "and LATENCY_OUTPUT_DIR."
        )
    config = yaml.safe_load(raw)
    config["_config_path"] = str(path.resolve())
    return config


def output_dir(config: dict[str, Any]) -> Path:
    return Path(config["paths"]["output_dir"])


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bh_adjust(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    order = np.argsort(values)
    ranked = values[order]
    adjusted = ranked * len(values) / np.arange(1, len(values) + 1)
    adjusted = np.minimum.accumulate(adjusted[::-1])[::-1]
    result = np.empty_like(adjusted)
    result[order] = np.minimum(adjusted, 1.0)
    return result


def _sample_indices(indices: np.ndarray, maximum: int, rng: np.random.Generator) -> np.ndarray:
    if len(indices) <= maximum:
        return indices
    return rng.choice(indices, size=maximum, replace=False)


def _load_split(
    data_dir: Path,
    days: list[str],
    max_per_class: int,
    seed: int,
    expected_features: list[str] | None,
) -> tuple[np.ndarray, np.ndarray, list[str], dict[str, Any]]:
    rng = np.random.default_rng(seed)
    class_parts: dict[int, list[np.ndarray]] = {0: [], 1: []}
    day_manifest: dict[str, Any] = {}
    features = expected_features

    for day_index, filename in enumerate(days):
        path = data_dir / filename
        if not path.exists():
            raise FileNotFoundError(f"Dataset file not found: {path}")
        frame = pd.read_csv(path)
        missing = [column for column in REQUIRED_META_COLUMNS if column not in frame]
        if missing:
            raise ValueError(f"{filename} misses columns: {missing}")

        current_features = [column for column in frame.columns if column not in DROP_COLUMNS]
        if features is None:
            features = current_features
        if current_features != features:
            raise ValueError(f"Feature schema/order mismatch in {filename}")

        attempted = frame["Attempted Category"].fillna(-1).ne(-1).to_numpy()
        original_label = frame["Label"].astype(str)
        labels = (original_label.ne("BENIGN").to_numpy() & ~attempted).astype(np.int8)
        values = frame[features].to_numpy(dtype=np.float64, copy=False)
        finite = np.isfinite(values).all(axis=1)
        labels = labels[finite]
        values = values[finite]

        counts = {str(key): int(value) for key, value in original_label.value_counts().items()}
        day_manifest[filename] = {
            "sha256": sha256(path),
            "rows": int(len(frame)),
            "finite_rows": int(finite.sum()),
            "attempted_relabelled_benign": int(attempted.sum()),
            "effective_benign": int((labels == 0).sum()),
            "effective_malicious": int((labels == 1).sum()),
            "original_labels": counts,
        }

        for class_id in (0, 1):
            indices = np.flatnonzero(labels == class_id)
            # Bound each day before concatenation to keep memory use predictable.
            selected = _sample_indices(indices, max_per_class, np.random.default_rng(seed + day_index * 17 + class_id))
            if len(selected):
                class_parts[class_id].append(np.asarray(values[selected], dtype=np.float64))

        del frame, values

    assert features is not None
    selected_parts = []
    selected_labels = []
    for class_id in (0, 1):
        if not class_parts[class_id]:
            raise ValueError(f"No class {class_id} records in split days {days}")
        candidates = np.concatenate(class_parts[class_id], axis=0)
        indices = _sample_indices(np.arange(len(candidates)), max_per_class, rng)
        selected_parts.append(candidates[indices])
        selected_labels.append(np.full(len(indices), class_id, dtype=np.int8))

    x = np.concatenate(selected_parts, axis=0)
    y = np.concatenate(selected_labels, axis=0)
    order = rng.permutation(len(y))
    return x[order], y[order], features, day_manifest


def prepare(config: dict[str, Any]) -> None:
    root = output_dir(config)
    processed = root / "processed"
    processed.mkdir(parents=True, exist_ok=True)
    destination = processed / "dataset.npz"
    if destination.exists():
        raise FileExistsError(f"Prepared dataset already exists: {destination}")

    data_dir = Path(config["paths"]["data_dir"])
    seed = int(config["seed"])
    arrays: dict[str, np.ndarray] = {}
    manifest: dict[str, Any] = {"seed": seed, "splits": {}, "features": None}
    features: list[str] | None = None

    for split_index, split_name in enumerate(("train", "validation", "test")):
        spec = config["data"]["splits"][split_name]
        x, y, features, days = _load_split(
            data_dir,
            list(spec["days"]),
            int(spec["max_per_class"]),
            seed + split_index * 10_000,
            features,
        )
        arrays[f"X_{split_name}"] = x
        arrays[f"y_{split_name}"] = y
        manifest["splits"][split_name] = {
            "days": days,
            "selected_rows": int(len(y)),
            "selected_benign": int((y == 0).sum()),
            "selected_malicious": int((y == 1).sum()),
        }

    arrays["feature_names"] = np.asarray(features, dtype=str)
    manifest["features"] = features
    np.savez_compressed(destination, **arrays)
    write_json(processed / "dataset_manifest.json", manifest)
    print(f"Prepared {destination} with {len(features)} features")


def model_factories(seed: int) -> dict[str, Any]:
    return {
        "LoR": Pipeline(
            [("scale", StandardScaler()), ("model", LogisticRegression(max_iter=1000, random_state=seed))]
        ),
        "SGD": Pipeline(
            [
                ("scale", StandardScaler()),
                ("model", SGDClassifier(loss="log_loss", max_iter=2000, tol=1e-4, random_state=seed)),
            ]
        ),
        "NB": GaussianNB(),
        "DT": DecisionTreeClassifier(min_samples_leaf=2, random_state=seed),
        "RF": RandomForestClassifier(
            n_estimators=100, min_samples_leaf=2, n_jobs=1, random_state=seed
        ),
        "GB": GradientBoostingClassifier(n_estimators=100, random_state=seed),
        "AB": AdaBoostClassifier(n_estimators=100, algorithm="SAMME", random_state=seed),
        "MLP": Pipeline(
            [
                ("scale", StandardScaler()),
                (
                    "model",
                    MLPClassifier(
                        hidden_layer_sizes=(64, 32),
                        max_iter=200,
                        early_stopping=True,
                        random_state=seed,
                    ),
                ),
            ]
        ),
    }


def _score_vector(model: Any, x: np.ndarray) -> np.ndarray:
    if hasattr(model, "predict_proba"):
        return np.asarray(model.predict_proba(x))[:, 1]
    if hasattr(model, "decision_function"):
        return np.asarray(model.decision_function(x))
    return np.asarray(model.predict(x), dtype=float)


def _score_method(model: Any) -> str:
    if hasattr(model, "predict_proba"):
        return "predict_proba_positive_class"
    if hasattr(model, "decision_function"):
        return "decision_function"
    return "hard_prediction"


def predictive_metrics(model_name: str, split: str, model: Any, x: np.ndarray, y: np.ndarray) -> dict[str, Any]:
    predicted = np.asarray(model.predict(x), dtype=int)
    scores = _score_vector(model, x)
    tn, fp, fn, tp = confusion_matrix(y, predicted, labels=[0, 1]).ravel()
    return {
        "model": model_name,
        "split": split,
        "n": len(y),
        "malicious_fraction": float(y.mean()),
        "accuracy": accuracy_score(y, predicted),
        "balanced_accuracy": balanced_accuracy_score(y, predicted),
        "precision": precision_score(y, predicted, zero_division=0),
        "recall": recall_score(y, predicted, zero_division=0),
        "f1": f1_score(y, predicted, zero_division=0),
        "mcc": matthews_corrcoef(y, predicted),
        "average_precision": average_precision_score(y, scores),
        "roc_auc": roc_auc_score(y, scores),
        "false_positive_rate": fp / (fp + tn) if fp + tn else np.nan,
        "tn": int(tn),
        "fp": int(fp),
        "fn": int(fn),
        "tp": int(tp),
    }


def _prevalence_scenario(
    x: np.ndarray,
    y: np.ndarray,
    malicious_fraction: float,
    max_samples: int,
    seed: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Construct the largest no-replacement sample up to max_samples."""
    benign = np.flatnonzero(y == 0)
    malicious = np.flatnonzero(y == 1)
    if not 0 < malicious_fraction < 1:
        raise ValueError("Predictive prevalence scenarios must be between zero and one")
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
    return x[indices], y[indices]


def train(config: dict[str, Any]) -> None:
    root = output_dir(config)
    data_path = root / "processed" / "dataset.npz"
    model_dir = root / "models"
    model_dir.mkdir(parents=True, exist_ok=True)
    existing = list(model_dir.glob("*.joblib"))
    if existing:
        raise FileExistsError(f"Model directory is not empty: {model_dir}")
    data = np.load(data_path)
    x_train, y_train = data["X_train"], data["y_train"]
    factories = model_factories(int(config["seed"]))
    requested = list(config["models"])
    rows = []
    timings = {}
    parameters = {}
    score_arrays: dict[str, np.ndarray] = {
        "models": np.asarray(requested, dtype=str),
        "y_validation": np.asarray(data["y_validation"], dtype=np.int8),
        "y_test": np.asarray(data["y_test"], dtype=np.int8),
    }
    score_methods: dict[str, str] = {}

    with threadpool_limits(limits=1):
        for name in requested:
            model = clone(factories[name])
            before = time.perf_counter()
            model.fit(x_train, y_train)
            timings[name] = time.perf_counter() - before
            parameters[name] = {key: repr(value) for key, value in model.get_params(deep=True).items()}
            joblib.dump(model, model_dir / f"{name}.joblib", compress=3)
            score_methods[name] = _score_method(model)
            for split in ("validation", "test"):
                scores = np.asarray(_score_vector(model, data[f"X_{split}"]), dtype=np.float64)
                if scores.shape != data[f"y_{split}"].shape or not np.isfinite(scores).all():
                    raise ValueError(f"Invalid exported scores for {name}/{split}: {scores.shape}")
                score_arrays[f"scores_{name}_{split}"] = scores
            for split in ("validation", "test"):
                rows.append(
                    predictive_metrics(
                        name,
                        split,
                        model,
                        data[f"X_{split}"],
                        data[f"y_{split}"],
                    )
                )
            for scenario_index, fraction in enumerate(config["evaluation"]["malicious_fractions"]):
                scenario_x, scenario_y = _prevalence_scenario(
                    data["X_test"],
                    data["y_test"],
                    float(fraction),
                    int(config["evaluation"]["max_samples"]),
                    int(config["seed"]) + scenario_index * 101,
                )
                rows.append(
                    predictive_metrics(
                        name,
                        f"test_prevalence_{float(fraction):.4f}",
                        model,
                        scenario_x,
                        scenario_y,
                    )
                )
            print(f"Trained {name} in {timings[name]:.2f}s")

    pd.DataFrame(rows).to_csv(root / "predictive_metrics.csv", index=False)
    np.savez_compressed(root / "prediction_scores.npz", **score_arrays)
    write_json(
        root / "prediction_scores_metadata.json",
        {
            "models": requested,
            "score_methods": score_methods,
            "validation_rows": int(len(data["y_validation"])),
            "test_rows": int(len(data["y_test"])),
            "selection_rule": "Select thresholds on validation only; evaluate the frozen thresholds on test.",
        },
    )
    write_json(
        root / "training_metadata.json",
        {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pandas": pd.__version__,
            "scipy": scipy.__version__,
            "scikit_learn": sklearn.__version__,
            "models": requested,
            "model_parameters": parameters,
            "training_seconds": timings,
            "threadpool_limit": 1,
            "prediction_score_export": "prediction_scores.npz",
        },
    )


def _underlying_model(model: Any) -> Any:
    return model.steps[-1][1] if isinstance(model, Pipeline) else model


def tree_path_nodes(model: Any, values: np.ndarray) -> float:
    estimator = _underlying_model(model)
    transformed = values
    if isinstance(model, Pipeline):
        transformed = model[:-1].transform(values)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        if hasattr(estimator, "tree_"):
            return float(np.mean(estimator.decision_path(transformed).getnnz(axis=1)))
        estimators = getattr(estimator, "estimators_", None)
        if estimators is None:
            return float("nan")
        counts = []
        for child in np.asarray(estimators, dtype=object).ravel():
            if hasattr(child, "decision_path"):
                counts.append(np.mean(child.decision_path(transformed).getnnz(axis=1)))
        return float(np.mean(counts)) if counts else float("nan")


def _make_batch(
    benign: np.ndarray,
    malicious: np.ndarray,
    batch_size: int,
    malicious_fraction: float,
    rng: np.random.Generator,
) -> tuple[np.ndarray, int]:
    if malicious_fraction <= 0:
        malicious_count = 0
    elif malicious_fraction >= 1:
        malicious_count = batch_size
    else:
        malicious_count = int(rng.binomial(batch_size, malicious_fraction))
    benign_count = batch_size - malicious_count
    parts = []
    if benign_count:
        parts.append(benign[rng.choice(len(benign), benign_count, replace=len(benign) < benign_count)])
    if malicious_count:
        parts.append(malicious[rng.choice(len(malicious), malicious_count, replace=len(malicious) < malicious_count)])
    values = np.concatenate(parts, axis=0)
    return values[rng.permutation(len(values))], malicious_count


def runtime_metadata(config: dict[str, Any], run_id: int) -> dict[str, Any]:
    affinity = None
    if hasattr(os, "sched_getaffinity"):
        affinity = sorted(os.sched_getaffinity(0))
    return {
        "run_id": run_id,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "numpy": np.__version__,
        "pandas": pd.__version__,
        "scipy": scipy.__version__,
        "scikit_learn": sklearn.__version__,
        "cpu_count": os.cpu_count(),
        "cpu_affinity": affinity,
        "one_cpu_affinity": affinity is not None and len(affinity) == 1,
        "threadpool_info": threadpool_info(),
        "docker": Path("/.dockerenv").exists(),
        "config": config["_config_path"],
    }


def _benchmark_worker(config_path: str, run_id: int) -> None:
    config = load_config(Path(config_path))
    root = output_dir(config)
    raw_dir = root / "benchmark" / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    data = np.load(root / "processed" / "dataset.npz")
    x_test, y_test = data["X_test"], data["y_test"]
    pools = {0: x_test[y_test == 0], 1: x_test[y_test == 1]}
    models = {name: joblib.load(root / "models" / f"{name}.joblib") for name in config["models"]}
    spec = config["benchmark"]
    seed = int(config["seed"]) + run_id * 1_000_003
    random.seed(seed)
    np.random.seed(seed)
    rng = np.random.default_rng(seed)

    batch_sizes = [int(value) for value in spec["batch_sizes"]]
    fractions = [float(value) for value in spec["malicious_fractions"]]
    repetitions = int(spec["repetitions"])
    warmup = int(spec["warmup"])

    with threadpool_limits(limits=1):
        for model in models.values():
            for batch_size in sorted({min(batch_sizes), max(batch_sizes)}):
                values, _ = _make_batch(pools[0], pools[1], batch_size, 0.5, rng)
                for _ in range(warmup):
                    model.predict(values)

    tasks = list(itertools.product(models, batch_sizes, fractions, range(repetitions)))
    rng.shuffle(tasks)
    rows = []
    started = time.perf_counter_ns()
    gc.disable()
    try:
        with threadpool_limits(limits=1):
            for sequence, (model_name, batch_size, fraction, repetition) in enumerate(tasks):
                values, malicious_count = _make_batch(
                    pools[0], pools[1], batch_size, fraction, rng
                )
                before = time.perf_counter_ns()
                models[model_name].predict(values)
                after = time.perf_counter_ns()
                elapsed_us = (after - before) / 1_000.0
                path_nodes = tree_path_nodes(models[model_name], values) if batch_size == 1 else np.nan
                rows.append(
                    {
                        "run_id": run_id,
                        "sequence": sequence,
                        "elapsed_since_start_ms": (before - started) / 1_000_000.0,
                        "model": model_name,
                        "batch_size": batch_size,
                        "requested_malicious_fraction": fraction,
                        "malicious_count": malicious_count,
                        "actual_malicious_fraction": malicious_count / batch_size,
                        "repetition": repetition,
                        "elapsed_us_total": elapsed_us,
                        "us_per_flow": elapsed_us / batch_size,
                        "throughput_flows_s": batch_size * 1_000_000.0 / elapsed_us,
                        "mean_tree_path_nodes": path_nodes,
                    }
                )
    finally:
        gc.enable()

    pd.DataFrame(rows).to_csv(raw_dir / f"run_{run_id:03d}.csv", index=False)
    write_json(raw_dir / f"metadata_{run_id:03d}.json", runtime_metadata(config, run_id))


def benchmark(config: dict[str, Any]) -> None:
    root = output_dir(config)
    raw_dir = root / "benchmark" / "raw"
    if raw_dir.exists() and list(raw_dir.glob("run_*.csv")):
        raise FileExistsError(f"Benchmark output already exists: {raw_dir}")
    process_runs = int(config["benchmark"]["process_runs"])
    context = mp.get_context("spawn")
    for run_id in range(process_runs):
        process = context.Process(target=_benchmark_worker, args=(config["_config_path"], run_id))
        process.start()
        process.join()
        if process.exitcode != 0:
            raise RuntimeError(f"Benchmark worker {run_id} failed with exit code {process.exitcode}")
        print(f"Completed independent benchmark process {run_id + 1}/{process_runs}")


def exact_sign_flip_p(differences: np.ndarray) -> float:
    differences = np.asarray(differences, dtype=float)
    if not len(differences) or np.allclose(differences, 0):
        return 1.0
    observed = abs(differences.mean())
    if len(differences) <= 18:
        extreme = 0
        total = 2 ** len(differences)
        for signs in itertools.product((-1.0, 1.0), repeat=len(differences)):
            if abs(np.mean(differences * np.asarray(signs))) >= observed - 1e-15:
                extreme += 1
        return extreme / total
    rng = np.random.default_rng(20260719)
    permutations = rng.choice((-1.0, 1.0), size=(100_000, len(differences)))
    return float((np.abs((permutations * differences).mean(axis=1)) >= observed).mean())


def class_effects(raw: pd.DataFrame) -> pd.DataFrame:
    pure = raw[raw["requested_malicious_fraction"].isin([0.0, 1.0])]
    run_means = (
        pure.groupby(["run_id", "model", "batch_size", "requested_malicious_fraction"])["us_per_flow"]
        .mean()
        .unstack("requested_malicious_fraction")
        .dropna()
    )
    rows = []
    for (model, batch_size), group in run_means.groupby(level=["model", "batch_size"]):
        benign = group[0.0].to_numpy()
        malicious = group[1.0].to_numpy()
        differences = benign - malicious
        n = len(differences)
        mean = float(differences.mean())
        sd = float(differences.std(ddof=1)) if n > 1 else np.nan
        critical = float(stats.t.ppf(0.975, n - 1)) if n > 1 else np.nan
        half = critical * sd / np.sqrt(n) if n > 1 else np.nan
        rows.append(
            {
                "model": model,
                "batch_size": batch_size,
                "n_independent_processes": n,
                "mean_benign_us_per_flow": float(benign.mean()),
                "mean_malicious_us_per_flow": float(malicious.mean()),
                "paired_difference_benign_minus_malicious_us": mean,
                "ci95_low_us": mean - half,
                "ci95_high_us": mean + half,
                "paired_cohen_dz": mean / sd if sd and np.isfinite(sd) else np.nan,
                "p_sign_flip_raw": exact_sign_flip_p(differences),
            }
        )
    result = pd.DataFrame(rows)
    result["p_bh"] = bh_adjust(result["p_sign_flip_raw"].to_numpy())
    result["significant_bh_0_05"] = result["p_bh"] < 0.05
    return result.sort_values(["batch_size", "model"])


def analyze(config: dict[str, Any]) -> None:
    root = output_dir(config)
    analysis_dir = root / "analysis"
    figures_dir = root / "figures"
    analysis_dir.mkdir(parents=True, exist_ok=True)
    figures_dir.mkdir(parents=True, exist_ok=True)
    files = sorted((root / "benchmark" / "raw").glob("run_*.csv"))
    if not files:
        raise FileNotFoundError("No raw benchmark CSVs were found")
    raw = pd.concat([pd.read_csv(path) for path in files], ignore_index=True)
    raw.to_csv(analysis_dir / "raw_combined.csv", index=False)

    group_columns = ["model", "batch_size", "requested_malicious_fraction"]
    summary = raw.groupby(group_columns).agg(
        n=("us_per_flow", "size"),
        process_runs=("run_id", "nunique"),
        actual_malicious_fraction=("actual_malicious_fraction", "mean"),
        mean_us_total=("elapsed_us_total", "mean"),
        mean_us_per_flow=("us_per_flow", "mean"),
        median_us_per_flow=("us_per_flow", "median"),
        sd_us_per_flow=("us_per_flow", "std"),
        p95_us_per_flow=("us_per_flow", lambda x: x.quantile(0.95)),
        p99_us_per_flow=("us_per_flow", lambda x: x.quantile(0.99)),
        mean_throughput_flows_s=("throughput_flows_s", "mean"),
    ).reset_index()
    summary.to_csv(analysis_dir / "timing_summary.csv", index=False)

    effects = class_effects(raw)
    effects.to_csv(analysis_dir / "class_effects.csv", index=False)

    path_rows = []
    paths = raw[(raw["batch_size"] == 1) & raw["mean_tree_path_nodes"].notna()]
    for model, group in paths.groupby("model"):
        if group["mean_tree_path_nodes"].nunique() < 2:
            rho, p_value = np.nan, np.nan
        else:
            result = stats.spearmanr(group["us_per_flow"], group["mean_tree_path_nodes"])
            rho, p_value = result.statistic, result.pvalue
        path_rows.append(
            {"model": model, "n": len(group), "spearman_rho": rho, "p_raw": p_value}
        )
    path_frame = pd.DataFrame(path_rows)
    if len(path_frame):
        path_frame["p_bh"] = np.nan
        valid = path_frame["p_raw"].notna()
        if valid.any():
            path_frame.loc[valid, "p_bh"] = bh_adjust(path_frame.loc[valid, "p_raw"].to_numpy())
    path_frame.to_csv(analysis_dir / "tree_path_correlations.csv", index=False)

    plot_data = summary.groupby(["model", "batch_size"], as_index=False).agg(
        median_us_per_flow=("median_us_per_flow", "median"),
        throughput=("mean_throughput_flows_s", "median"),
    )
    for metric, ylabel, filename in (
        ("median_us_per_flow", "Median latency (us/flow)", "latency_per_flow_vs_batch.png"),
        ("throughput", "Throughput (flows/s)", "throughput_vs_batch.png"),
    ):
        fig, axis = plt.subplots(figsize=(8, 5))
        for model, group in plot_data.groupby("model"):
            axis.plot(group["batch_size"], group[metric], marker="o", label=model)
        axis.set_xscale("log", base=2)
        ticks = sorted(plot_data["batch_size"].unique())
        axis.set_xticks(ticks)
        axis.set_xticklabels([str(value) for value in ticks])
        axis.set_yscale("log")
        axis.set_xlabel("Batch size")
        axis.set_ylabel(ylabel)
        axis.grid(True, which="both", alpha=0.25)
        axis.legend(ncol=2, fontsize=8)
        fig.tight_layout()
        fig.savefig(figures_dir / filename, dpi=200)
        plt.close(fig)

    print(f"Wrote analysis to {analysis_dir}")
    print(effects.to_string(index=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "train", "benchmark", "analyze", "all"])
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = load_config(args.config)

    if args.command in ("prepare", "all"):
        prepare(config)
    if args.command in ("train", "all"):
        train(config)
    if args.command in ("benchmark", "all"):
        benchmark(config)
    if args.command in ("analyze", "all"):
        analyze(config)


if __name__ == "__main__":
    main()
