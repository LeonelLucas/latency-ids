# Latency and Throughput in Flow-Based ML Intrusion Detection

This repository contains the complete reproducibility artifact for the study
**Latency and Throughput Trade-offs in Flow-Based ML Intrusion Detection: A
Reproducible Instance-vs-Batch Evaluation**.

The artifact downloads and verifies the corrected CNS2022 release of
CICIDS2017, constructs day-disjoint train/validation/test partitions, trains
eight classical classifiers, measures instance- and batch-based inference, and
produces predictive metrics, raw timing observations, statistical tests, and
figures. The definitive outputs reported in the paper are included under
[`results/paper`](results/paper/README.md).

## Fastest reproduction path

On a physical Linux host, run:

```bash
chmod +x run_definitive_linux.sh
LADC_CPU=3 bash run_definitive_linux.sh
```

Replace `3` with the logical CPU reserved for the benchmark. The runner:

1. installs missing host utilities and Docker when supported;
2. downloads the corrected dataset if the CSV files are not already present;
3. verifies the dataset with pinned SHA-256 hashes;
4. builds the pinned container image;
5. trains the models and runs 12 sequential process-level replications;
6. validates row counts, CPU affinity, thread limits, and output completeness;
7. creates a compact results archive and its SHA-256 checksum.

The definitive profile can take several hours. A short workflow check is
available with:

```bash
LADC_PROFILE=smoke LADC_STRICT_CONTROLS=0 bash run_definitive_linux.sh
```

Smoke-test timings and p-values are not paper results.

## Experimental design

The predictive stage uses complete, disjoint CICIDS2017 days:

| Partition | Days | Role |
|---|---|---|
| Training | Monday-Wednesday | Fit eight classifiers |
| Validation | Thursday | Select the threshold used in sensitivity analysis |
| Test | Friday | Evaluate unseen flows and attack families; build timing pools |

The timing stage crosses the following factors independently on each host:

| Factor | Levels |
|---|---|
| Classifier | LoR, SGD, NB, DT, RF, GB, AB, MLP |
| Flows per `predict` call | 1, 8, 16, 32, 64, 100 |
| Requested malicious fraction | 0%, 1%, 5%, 10%, 50%, 100% |
| Calls per condition and process | 30 |
| Fresh sequential processes per host | 12 |

This yields 288 conditions, 8,640 timed calls per process, and 103,680 calls
per host. Across two hosts, the study contains 207,360 calls representing more
than 7.6 million classified flows.

The process run is the independent block for confirmatory class-composition
tests. Individual calls within one process are repeated observations, not 360
independent runtime executions. See
[`docs/EXPERIMENTAL_DESIGN.md`](docs/EXPERIMENTAL_DESIGN.md) for the full
hierarchy and [`PROTOCOL.md`](PROTOCOL.md) for the preregistered analysis logic.

## What is timed

Timing begins with a ready, unscaled NumPy matrix and ends immediately after
`Pipeline.predict` returns. It includes fitted model transformations, such as
standardization, but excludes CSV parsing, flow construction, batch formation,
queueing, and network transfer.

At the start of each fresh process, every model receives 20 untimed calls with
one flow and 20 untimed calls with 100 flows. The reported values therefore
characterize warmed-up inference, not model-loading or cold-start latency.

## Repository layout

```text
configs/                 smoke and definitive experiment profiles
docs/                    design, outputs, and troubleshooting documentation
latency_artifact/        data, training, timing, analysis, and plotting code
results/paper/           complete compact outputs for Host-LC and Host-SW
scripts/                 host metadata helpers
Dockerfile               pinned Python execution environment
compose.yaml             manual Docker Compose entry point
run_definitive_linux.sh  self-contained one-command Linux runner
```

## Manual Docker execution

The one-command runner is recommended because it records host telemetry and
validates the result package. For stage-by-stage inspection, place the five
CSV files in `../source/datasets/CICIDS2017_improved_CNS2022/` and run:

```bash
docker compose build
PROFILE=smoke CPUSET=0 docker compose run --rm artifact
```

Individual stages are `prepare`, `train`, `benchmark`, and `analyze`:

```bash
docker compose run --rm artifact prepare --config configs/smoke.yaml
```

## Reproducibility boundary

Docker pins the software stack; it cannot make latency hardware-independent.
Processor model, frequency scaling, turbo policy, temperature, kernel activity,
and background load remain part of the physical execution environment. The
runner records these variables and pins the benchmark to one logical CPU with
one numerical-library thread.

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for Docker daemon,
CPU-governor, and host-load problems, and [`docs/OUTPUTS.md`](docs/OUTPUTS.md)
for a description of every result family.

## Citation

Citation metadata are provided in [`CITATION.cff`](CITATION.cff). The paper
bibliographic entry will be added after publication.

## License

The source code and documentation are released under the MIT License. The
CICIDS2017/CNS2022 data are not redistributed and remain subject to their
original terms.
