# Latency-Aware Evaluation of Flow-Based ML-IDS

<p align="center">
  <strong>
    A reproducible experimental artifact for evaluating latency,
    throughput, batching, traffic composition, and cross-host robustness
    in flow-based Machine Learning Intrusion Detection Systems.
  </strong>
</p>

<p align="center">
  <code>4 datasets</code> ·
  <code>8 ML models</code> ·
  <code>6 batch sizes</code> ·
  <code>6 traffic compositions</code> ·
  <code>12 independent processes</code> ·
  <code>3 physical hosts</code>
</p>

---

## Overview

This repository provides a reproducible experimental artifact for evaluating predictive quality and inference performance in flow-based Machine Learning Intrusion Detection Systems (ML-IDS). The study examines how model choice, inference granularity, traffic composition, and execution platform affect inference service time, amortized per-flow cost, and throughput.

## Experimental Methodology

<p align="center">
  <img src="docs/images/metodologia.png" alt="Experimental methodology: dataset preparation, classifiers, inference configurations, execution platforms, measurement protocol, and statistical analysis" width="100%">
</p>
<p align="center"><em>Figure 1. Experimental workflow (original dissertation figure, in Portuguese).</em></p>

The workflow comprises dataset-specific feature selection, temporal partitioning and sampling; training and predictive evaluation of eight classifiers; inference under varying batch sizes and malicious-flow fractions; controlled execution on three physical platforms; and statistical analysis of predictive and computational outcomes. Predictive evaluation includes accuracy, average precision (AP), ROC-AUC, and precision.

## Experimental Design

| Dimension | Configuration |
|---|---|
| Datasets | 4 |
| Models | 8 |
| Batch sizes | 1, 8, 16, 32, 64, 100 |
| Requested malicious fractions | 0%, 1%, 5%, 10%, 50%, 100% |
| Repetitions per condition and process | 30 |
| Independent processes | 12 |
| Warm-up iterations | 20 |
| Physical hosts | 3 |
| Conditions per dataset | 288 |
| Timing observations per dataset and host | 103,680 |
| Timing observations per host | 414,720 |
| Total timing observations | 1,244,160 |

The timing observation count per dataset and host is `8 × 6 × 6 × 30 × 12 = 103,680`. Requested malicious fractions define the experimental conditions; their realization is constrained by integer batch sizes.

## Datasets

| Dataset | Description |
|---|---|
| CICIDS2017 | Corrected version of CICIDS2017 |
| GenIDS-CIC17 | GenIDS dataset associated with CICIDS2017 |
| GenIDS-UNSW15 | GenIDS dataset associated with UNSW-NB15 |
| GenIDS-CIC18 | GenIDS dataset associated with CICIDS2018 |

Dataset-specific preparation precedes the common training and timing pipeline. On Raspberry Pi, GenIDS-CIC18 uses a memory-compatible [V2 subset](https://github.com/LeonelLucas/latency-ids/releases/tag/raspberry-datasets-v1.0); this input difference must be considered in cross-host comparisons.

---

## Machine Learning Models

Eight machine learning models are evaluated.

| Machine learning model |
|---|
| Logistic Regression (LoR) |
| Stochastic Gradient Descent with Logistic Loss (SGD) |
| Gaussian Naive Bayes (NB) |
| Decision Tree (DT) |
| Random Forest (RF) |
| Gradient Boosting (GB) |
| AdaBoost (AB) |
| Multilayer Perceptron (MLP) |

---

## Measurement Boundary and Metrics

The benchmark measures model inference service time, not end-to-end IDS latency. It does not include network capture, flow construction, or waiting for a batch to form.

For a batch of size `b` with measured service time `L(b)` in seconds:

- **Inference latency:** `L(b)`, the duration of the complete inference call.
- **Amortized per-flow cost:** `L(b) / b`.
- **Throughput:** `b / L(b)`, in flows per second.

For `b = 1`, call latency and per-flow cost coincide. For larger batches, amortized cost is not the response time experienced by an individual flow. Predictive quality and computational performance are evaluated separately.

---

## Execution Platforms and Results

| Host | Architecture | Platform | Original run directory |
|---|---|---|---|
| Morty (Host-SW) | x86-64 | Linux | [multidataset-run-20260930T225117Z](multidataset-run-20260930T225117Z/) |
| Cartman (Host-LC) | x86-64 | Linux, Intel Core i7-3770 | [multidataset-run-20261112T012654Z](multidataset-run-20261112T012654Z/) |
| Raspberry Pi | ARM64 | Raspberry Pi 3 Model B | [Results](multidataset-run-20261101T205354Z/) |

Each host completed the four-dataset evaluation independently. Host labels describe execution contexts rather than hardware quality. Absolute timing values need not be identical across platforms.

---

## Controlled Host Execution

The definitive runner performs host checks and records execution
metadata to improve the reproducibility and auditability of the
experiment.

The controls include:

- explicit CPU selection;
- CPU availability verification;
- CPU governor verification;
- host-load checks before benchmarking;
- host monitoring during benchmark execution;
- cooldown periods between dataset executions;
- execution-environment capture;
- dataset-specific logs;
- result validation;
- artifact packaging; and
- SHA-256 integrity verification.

### CPU Governor

The selected benchmark CPU is required to use the:

```text
performance
```

governor.

The runner checks this requirement before the definitive experiment
continues.

### Quiet-Host Gate

Before benchmark execution, the runner checks the host load.

The default maximum accepted one-minute load average is:

```text
0.50
```

If the host exceeds this threshold, the runner waits for the load to
fall within the accepted range before continuing, subject to the
configured waiting period.

### Host Monitoring

During benchmark execution, host information is periodically recorded.

The monitoring infrastructure records information including system load
and, when available, selected CPU frequency and thermal information.

The monitoring process is kept separate from the selected benchmark CPU
when the host configuration permits it.

---

## Cooldown Between Datasets

The four datasets are executed sequentially.

A cooldown interval is used between dataset executions to reduce the
risk that the immediately preceding experiment influences the next one
through transient host state.

The default configured cooldown interval is:

```text
30 seconds
```

---

## Requirements

The definitive experiment is designed for a Linux execution environment
with Docker and the host-level interfaces required by the experimental
controls.

At minimum, the execution environment must provide the tools and
permissions required by the repository and definitive runner.

Important host-side dependencies include:

```text
Linux
Docker
Bash
Python 3
taskset
standard GNU/Linux command-line utilities
```

The benchmark environment itself is built and executed according to the
repository configuration.

The definitive runner performs additional validation before benchmark
execution and stops when mandatory experimental requirements are not
satisfied.

---

## Dataset Availability

Before starting the multi-dataset runner, make the required source datasets available in the expected locations. The individual Raspberry Pi runners automate acquisition and integrity verification. Consult the dataset preparation scripts and configuration files for the required source organization.

---

## Definitive Experiment Runner

The complete multi-dataset experiment on one physical host is executed
with:

```bash
./run_all_datasets_definitive.sh
```

The runner validates the required inputs and then executes the complete
four-dataset workflow.

At a high level:

```text
Validate datasets
       |
       v
Build experiment image
       |
       v
CICIDS2017
       |
       v
Validate outputs
       |
       v
GenIDS-CIC17
       |
       v
Validate outputs
       |
       v
GenIDS-UNSW15
       |
       v
Validate outputs
       |
       v
GenIDS-CIC18
       |
       v
Validate outputs
       |
       v
Create final package
```

The definitive runner does not automatically perform cross-host comparison.

The experiment should be executed from the repository root using the
frozen experimental version documented for the corresponding run.

A definitive execution should be allowed to complete without modifying
the experimental code or configuration during the run.

Each physical host performs its own independent complete execution.

### Individual Dataset Runners for Raspberry Pi

The scripts in `runners_raspberry/` allow each dataset to be executed
independently, including automatic dataset acquisition, integrity
verification, preparation, training, benchmarking, analysis, and validation.
From the repository root, select the desired command:

```bash
bash runners_raspberry/run_cicids2017.sh
bash runners_raspberry/run_genids_cic17.sh
bash runners_raspberry/run_genids_unsw15.sh
bash runners_raspberry/run_genids_cic18.sh
```

The runners require ARM64 Linux, Docker with the `latency-ids:raspberry-pi`
image, adequate swap, stable power, cooling, and the `performance` CPU
governor. Benchmark execution uses CPU 3 and one computational thread.
The original Raspberry Pi runs were completed and validated; the later
automated runners have not been fully re-executed end to end.

---

## Output Organization

Each definitive host execution creates an independent run directory.

The general structure is:

```text
multidataset-run-<timestamp>/
├── results/
│   ├── cicids2017/
│   ├── genids_cic17/
│   ├── genids_unsw15/
│   └── genids_cic18/
├── host/
│   ├── cicids2017/
│   ├── genids_cic17/
│   ├── genids_unsw15/
│   └── genids_cic18/
└── logs/
    ├── cicids2017/
    ├── genids_cic17/
    ├── genids_unsw15/
    └── genids_cic18/
```

This organization keeps benchmark results, host information, and
execution logs separated by dataset.

### Dataset Results

Each dataset has its own result directory under:

```text
results/<dataset>/
```

The result directory contains the artifacts generated by the
dataset-specific experiment and subsequent analysis.

A particularly important file for post-hoc cross-host comparison is:

```text
results/<dataset>/analysis/timing_summary.csv
```

This file contains the timing summary used to match equivalent
experimental conditions between the two physical hosts.

For the complete four-dataset execution, the required timing summaries
are therefore:

```text
results/cicids2017/analysis/timing_summary.csv
results/genids_cic17/analysis/timing_summary.csv
results/genids_unsw15/analysis/timing_summary.csv
results/genids_cic18/analysis/timing_summary.csv
```

### Host Information

Host-specific information is stored separately under:

```text
host/<dataset>/
```

This directory preserves information collected around each dataset
execution, including the quiet-host check, benchmark monitoring, and
host-state captures.

Examples include:

```text
quiet_host_check.txt
benchmark_monitor.csv
monitor_affinity.txt
host_<phase>.txt
```

The exact host information available may depend on the operating system
and hardware interfaces exposed by the machine.

### Logs

Dataset-specific execution logs are stored under:

```text
logs/<dataset>/
```

Keeping logs separated by dataset simplifies inspection of the complete
multi-dataset execution and helps identify the stage associated with a
particular message or failure.

---

## Final Result Package

After all four datasets have completed successfully, the definitive
runner creates a final result package.

The package preserves the experiment outputs together with the
information required to inspect and audit the execution.

The packaged artifact includes experimental results, analysis outputs,
host information, logs, and a snapshot of the relevant experimental
infrastructure.

A compressed archive is generated in the form:

```text
multidataset-results-<timestamp>.tar.gz
```

A corresponding SHA-256 checksum file is also generated:

```text
multidataset-results-<timestamp>.tar.gz.sha256
```

The checksum can be verified with:

```bash
sha256sum -c multidataset-results-<timestamp>.tar.gz.sha256
```

A successful verification should report:

```text
OK
```

This provides an integrity check for transferring or archiving the
complete host execution.

---

## Artifact Snapshot

The final package includes a snapshot of the experimental infrastructure
used for the execution.

This is important because reproducibility depends not only on preserving
numerical results, but also on preserving the code and configuration
associated with those results.

The snapshot includes the relevant experiment implementation and
supporting scripts available at packaging time.

The package also contains SHA-256 hashes for its internal files, allowing
the preserved artifact contents to be checked for integrity.

---

## Post-Hoc Cross-Host Comparison

The repository provides a dedicated wrapper for comparing two complete
host executions:

```text
compare_two_hosts.sh
```

The comparison is intentionally invoked manually after the two host
result directories are available.

General usage:

```bash
./compare_two_hosts.sh HOST_A_RUN HOST_B_RUN [OUTPUT_DIR]
```

For example:

```bash
./compare_two_hosts.sh \
    /path/to/host-a/multidataset-run-<timestamp> \
    /path/to/host-b/multidataset-run-<timestamp> \
    ./cross-host-analysis
```

The first argument is the complete run directory produced by the first
physical host.

The second argument is the complete run directory produced by the second
physical host.

The third argument is optional and specifies where the cross-host
analysis should be written.

If an explicit output directory is not supplied, the wrapper creates a
timestamped cross-host analysis directory.

### Comparing the Three Hosts

The wrapper operates on two hosts at a time. Assign the actual complete
run directories using their host metadata, rather than timestamp order:

```bash
MORTY="/path/to/morty-run"
CARTMAN="/path/to/cartman-run"
RASPBERRY="/path/to/raspberry-run"

./compare_two_hosts.sh "$MORTY" "$CARTMAN" cross-host-analysis-morty-vs-cartman
./compare_two_hosts.sh "$MORTY" "$RASPBERRY" cross-host-analysis-morty-vs-raspberry
./compare_two_hosts.sh "$CARTMAN" "$RASPBERRY" cross-host-analysis-cartman-vs-raspberry
```

These commands describe the comparison workflow, not a claim that all
three pairwise analyses have already been completed.

---

## Cross-Host Validation

Before performing the comparison, the wrapper checks whether both host
executions contain the required timing summary for every dataset:

```text
CICIDS2017
GenIDS-CIC17
GenIDS-UNSW15
GenIDS-CIC18
```

For each dataset, both hosts must contain:

```text
results/<dataset>/analysis/timing_summary.csv
```

The comparison stops if a required timing summary is missing.

This prevents a partial host execution from being silently treated as a
complete four-dataset replication.

---

## Cross-Host Output

The complete post-hoc analysis produces dataset-level comparisons and an
aggregate four-dataset summary.

For each dataset, equivalent experimental conditions from Host A and
Host B are matched and compared.

The aggregate comparison contains one summary entry for each of the four
datasets and reports the number of matched conditions together with the
cross-host statistics.

The complete design expects:

```text
288 matched conditions per dataset and host pair
1,152 matched conditions across four datasets per host pair
3,456 matched-condition comparisons across three host pairs
```

Cross-host outputs include the statistics required to inspect absolute
latency differences and rank consistency between the two execution
environments.

The detailed comparison infrastructure is implemented by:

```text
scripts/compare_hosts.py
scripts/compare_all_hosts.py
```

The shell wrapper:

```text
compare_two_hosts.sh
```

provides the normal user-facing entry point for the complete post-hoc
comparison.

---

## Cross-Host Statistics

The post-hoc comparison evaluates both absolute timing differences and
rank consistency.

### Latency Ratios

Latency ratios describe the relative execution speed of equivalent
conditions on the two hosts.

These ratios characterize differences in absolute timing between the
physical systems.

### Cross-Host Spearman Rank Correlation

For the post-hoc cross-host comparison, Spearman rank correlation
evaluates whether the relative ordering of matched experimental
conditions remains consistent across the two physical hosts.

This cross-host statistic is distinct from the separate tree-path
Spearman analysis described in the experimental protocol. The tree-path
analysis investigates the relationship between tree-path behavior and
latency, whereas the cross-host statistic evaluates rank consistency
between equivalent conditions executed on different hosts.

Two hosts may therefore have different absolute latencies while still
producing very similar rankings among models and experimental
configurations. High cross-host rank consistency must not be interpreted
as evidence that the hosts have identical absolute performance.

---

## Repository Entry Points

The principal entry points for the definitive experiment are:

| File | Purpose |
|---|---|
| `run_all_datasets_definitive.sh` | Executes the complete four-dataset definitive experiment on one host |
| `runners_raspberry/` | Executes individual datasets on Raspberry Pi (see Individual Dataset Runners above) |
| `compare_two_hosts.sh` | Runs the manual post-hoc comparison between two complete physical-host executions |
| `scripts/compare_all_hosts.py` | Coordinates cross-host comparison across all four datasets |
| `scripts/compare_hosts.py` | Performs matched-condition cross-host statistical comparison |
| `PROTOCOL.md` | Documents the definitive experimental methodology |

The dataset preparation and experiment implementation are contained in
the corresponding repository scripts and `latency_artifact` components.

---

## Repository Structure

The repository separates experimental implementation, configuration,
documentation, execution scripts, and generated results.

A high-level view is:

```text
latency-ids/
├── configs/
├── docs/
│   └── images/
│       └── metodologia.png
├── latency_artifact/
├── results/
├── scripts/
├── runners_raspberry/
├── CITATION.cff
├── Dockerfile
├── LICENSE
├── Makefile
├── PROTOCOL.md
├── README.md
├── compare_two_hosts.sh
├── compose.yaml
├── requirements.txt
└── run_all_datasets_definitive.sh
```

The exact contents of generated result directories depend on the
execution stage and dataset, while the definitive runner maintains a
common high-level organization for all four datasets.

---

## Protocol Documentation

The detailed experimental protocol is documented in:

```text
PROTOCOL.md
```

The README provides the high-level description and reproduction
workflow, while `PROTOCOL.md` should be consulted for the detailed
experimental methodology, measurement design, controls, and analysis
rules.

When reproducing or extending the experiment, the protocol should be
considered together with the frozen implementation used to generate the
corresponding results.

---

## Extending the Experiment

The repository is structured so that additional datasets can be
integrated while preserving a common experimental methodology.

A new dataset should not simply be passed directly to the benchmark
without considering its schema and semantics.

Instead, integration should preserve the separation:

```text
New dataset
    |
    v
Dataset-specific preparation
    |
    v
Validation
    |
    v
Common experimental representation
    |
    v
Existing training and timing pipeline
```

Any extension should document changes to preprocessing, feature
selection, labeling, sampling, model configuration, timing methodology,
or host controls.

Results produced under a modified protocol should be clearly
distinguished from results produced by the definitive configuration
documented in this repository.

---

## Result Preservation

For reproducibility, the complete output of each physical-host execution
should be preserved.

In particular, retain:

```text
the complete run directory
the generated result package
the SHA-256 checksum file
host metadata
benchmark monitoring data
execution logs
analysis outputs
the corresponding repository revision
```

All three host executions should remain identifiable as independent
experimental runs.

Cross-host analysis outputs should also be preserved separately rather
than replacing either host's original measurements.

---

## Reproducibility Checklist

Before considering a host execution complete, verify that:

- all four datasets were evaluated;
- the selected runners completed successfully;
- the expected dataset-level analyses were generated;
- host metadata was preserved;
- benchmark monitoring information was preserved;
- the final package was created, where applicable;
- the package checksum verifies successfully, where applicable; and
- the repository revision associated with the execution is known.

Before performing the cross-host comparison, verify that:

- both physical-host executions are complete;
- both executions correspond to the intended experimental methodology;
- all four `timing_summary.csv` files exist for each host; and
- the original host results remain unchanged.

After the comparison, preserve the generated cross-host analysis
alongside the independent host artifacts.

---

## Citation

If this repository or its experimental artifacts are used in academic
work, please cite the corresponding research work and use the repository
citation metadata when applicable.

Citation metadata is provided in:

```text
CITATION.cff
```

When reporting experimental results, the repository revision and the
corresponding preserved experimental artifacts should also be recorded
whenever possible.

---

## License

See:

```text
LICENSE
```

for the licensing terms applicable to this repository.
