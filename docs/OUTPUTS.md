# Output reference

The default output root is `results/<profile>/`.

## Prepared data and training

- `processed/dataset.npz`: deterministic sampled matrices and labels. Omitted
  from compact paper bundles because it can be regenerated.
- `processed/dataset_manifest.json`: source hashes, schema, selected features,
  split sizes, and class counts.
- `models/*.joblib`: fitted pipelines. Omitted from compact paper bundles;
  hashes are retained.
- `training_metadata.json`: model settings and software metadata.
- `predictive_metrics.csv`: validation, balanced-test, and prevalence-specific
  predictive metrics.
- `prediction_scores.npz`: exported continuous scores and labels.
- `prediction_scores_metadata.json`: score-array dimensions and provenance.

## Raw timing

- `benchmark/raw/timing_NNN.csv`: raw calls from process run `NNN` in a full
  local execution. The compact paper bundles combine these files instead.
- `benchmark/raw/metadata_NNN.json`: process ID, CPU affinity, thread-pool
  limits, timing clock, and runtime metadata.
- `analysis/raw_combined.csv`: all call-level observations for one host.

Important columns include classifier, call size, requested and realized
malicious fractions, process run, randomized sequence position, total latency,
per-flow latency, and throughput.

## Analysis

- `analysis/timing_summary.csv`: 360-call descriptive summary for every
  classifier/call-size/composition condition.
- `analysis/class_effects.csv`: process-paired benign-versus-malicious tests.
- `analysis/tree_path_correlations.csv`: decision-path/latency correlations for
  applicable tree models at call size 1.
- `figures/latency_per_flow_vs_batch.png`: amortized latency by call size.
- `figures/throughput_vs_batch.png`: achieved throughput by call size.

## Host evidence and validation

- `host/host_before.txt`, `host_pre_benchmark.txt`, `host_after.txt`: hardware,
  kernel, frequency policy, load, processes, and Docker metadata.
- `host/host_monitor.csv`: load, selected-CPU frequency, and thermal telemetry.
- `validation/validation_report.txt`: expected files, counts, dimensions, CPU
  affinity, and thread-limit checks.
- `logs/experiment.log`: stage-level execution log.
- `excluded_model_sha256.txt` and `excluded_dataset_npz_sha256.txt`: hashes for
  large reproducible files intentionally omitted from compact bundles.
