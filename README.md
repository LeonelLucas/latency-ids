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
  <code>2 physical hosts</code>
</p>

---

## Overview

Machine Learning Intrusion Detection Systems (ML-IDS) are commonly
evaluated primarily through predictive metrics. However, deployment also
depends on computational behavior: how quickly network flows can be
processed, how batching changes inference cost, how traffic composition
affects inference behavior, and whether experimental conclusions remain
consistent across independent execution environments.

This repository provides the reproducible experimental infrastructure
for a controlled multi-dataset evaluation of these aspects.

The definitive experiment evaluates four network intrusion datasets,
eight machine learning models, multiple batch sizes and traffic
compositions, repeated measurements across independent processes, and
replication on two physical Linux hosts.

The workflow separates dataset preparation, model training, definitive
timing measurements, dataset-level analysis, result packaging, and
post-hoc cross-host comparison.

---

## Experimental Design

The definitive experiment follows the same high-level measurement
protocol across all four datasets.

| Dimension | Configuration |
|---|---|
| Datasets | 4 |
| Machine learning models | 8 |
| Batch sizes | 1, 8, 16, 32, 64, 100 |
| Requested malicious fractions | 0.00, 0.01, 0.05, 0.10, 0.50, 1.00 |
| Repetitions | 30 |
| Independent processes | 12 |
| Warm-up iterations | 20 |
| Physical hosts | 2 |

The combination of model, batch size, and requested malicious fraction
defines the experimental conditions evaluated by the timing pipeline.

Each condition is measured repeatedly, and the definitive protocol uses
independent processes to reduce dependence on the state of a single
long-running Python process.

The complete four-dataset experiment is independently replicated on two
physical Linux hosts.

The resulting definitive experimental scale is summarized below.

| Component | Definitive configuration |
|---|---|
| Datasets | CICIDS2017, GenIDS-CIC17, GenIDS-UNSW15, GenIDS-CIC18 |
| Machine learning models | 8 |
| Batch sizes | 1, 8, 16, 32, 64, 100 |
| Requested malicious fractions | 0.00, 0.01, 0.05, 0.10, 0.50, 1.00 |
| Repetitions | 30 |
| Independent processes | 12 |
| Warm-up iterations | 20 |
| Physical hosts | 2 |
| Conditions per dataset | 288 |
| Raw benchmark observations per dataset and host | 103,680 |
| Raw benchmark observations per host | 414,720 |
| Raw benchmark observations across two hosts | 829,440 |
| Cross-host matched conditions per dataset | 288 |

---

## Datasets

Four datasets are included in the definitive evaluation.

### CICIDS2017

CICIDS2017 is evaluated using the corrected version adopted by the
experimental pipeline.

The dataset-specific preparation stage converts the source data into the
representation expected by the common training and timing pipeline.

### GenIDS-CIC17

GenIDS-CIC17 provides an additional dataset associated with the
CICIDS2017 scenario.

Its dataset-specific preparation procedure is performed before the
common experimental pipeline so that the definitive timing methodology
can remain consistent across datasets.

### GenIDS-UNSW15

GenIDS-UNSW15 provides the GenIDS dataset associated with the UNSW-NB15
scenario.

As with the other datasets, dataset-specific preprocessing is separated
from the common benchmark methodology.

### GenIDS-CIC18

GenIDS-CIC18 provides the fourth dataset in the definitive evaluation
and is associated with the CICIDS2018 scenario.

It is prepared using its corresponding dataset-specific pipeline and is
then evaluated under the same definitive timing methodology used for the
other datasets.

### Common multi-dataset workflow

The definitive runner executes the datasets sequentially:

```text
CICIDS2017
    |
    v
GenIDS-CIC17
    |
    v
GenIDS-UNSW15
    |
    v
GenIDS-CIC18


```

Although dataset preparation is dataset-specific, the benchmark design
is kept consistent so that the resulting measurements can be analyzed
under the same experimental methodology.

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

The complete model name and its abbreviation are presented together
when each algorithm is introduced. Abbreviations may subsequently be
used as compact identifiers in result files, figures, tables, and
analysis outputs.

---

## Timing Dimensions

The experimental design focuses on inference-time behavior rather
than considering predictive performance alone.

Two central operational dimensions are latency and throughput.

### Latency

Latency represents the time required to perform model inference.

The experiment evaluates inference under different call sizes, ranging
from processing a single flow per call to processing multiple flows in
a batch.

The configured batch sizes are:

```text
1, 8, 16, 32, 64, 100
```

For batched execution, total call latency and per-flow timing can be
distinguished. This is important because the cost of one inference call
can be amortized across multiple flows.

### Throughput

Throughput represents the number of network flows that can be processed
per unit of time.

Batching may increase throughput by amortizing inference-call overhead,
but throughput and latency describe different operational properties and
must therefore be interpreted separately.

The experimental pipeline preserves the timing information required to investigate
this relationship.

---

## Traffic Composition

Inference behavior is evaluated under multiple requested malicious-flow
fractions.

The configured fractions are:

```text
0.00
0.01
0.05
0.10
0.50
1.00
```

These conditions range from entirely benign input to entirely malicious
input, with intermediate traffic compositions between the two extremes.

This design allows the analysis to investigate whether model inference
behavior is sensitive to the composition of the input flows.

---

## Repeated Measurement Strategy

Timing experiments are inherently sensitive to transient execution
conditions. The definitive experiment therefore uses repeated
measurements and independent processes.

The main configured parameters are:

```text
Repetitions:             30
Independent processes:   12
Warm-up iterations:      20
```

Warm-up iterations are performed before retained timing measurements.

Independent processes provide separate execution contexts for repeated
benchmarking rather than relying exclusively on repeated measurements
inside one persistent process.

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

## Two-Host Replication

The complete four-dataset experiment is independently executed on two
physical Linux hosts.

Each host performs the complete experiment and produces its own timing
results, host metadata, monitoring information, logs, and packaged
artifacts.

The hosts are not expected to exhibit identical absolute latency.
Differences in processor characteristics and system environments can
produce different absolute execution times.

The cross-host analysis therefore evaluates both absolute timing
differences and the consistency of experimental behavior across the two
independent physical environments.

---

## Cross-Host Analysis

Cross-host analysis is deliberately separated from benchmark execution.

Each definitive host execution produces and preserves its own results.
After complete executions from both physical hosts are available, the
cross-host analysis is invoked manually.

This separation keeps measurement generation distinct from subsequent
comparative analysis.

### Matched Experimental Conditions

Equivalent conditions from both hosts are matched using the experimental
configuration.

The comparison considers the same:

```text
model
batch size
requested malicious fraction
```

for each dataset.

Each dataset contains:

```text
8 models
x 6 batch sizes
x 6 requested malicious fractions
= 288 matched experimental conditions
```

Across four datasets, this corresponds to:

```text
288 x 4 = 1,152 matched cross-host conditions
```

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

The definitive runner does not automatically perform the two-host
comparison.

The experiment should be executed from the repository root using the
frozen experimental version documented for the corresponding run.

A definitive execution should be allowed to complete without modifying
the experimental code or configuration during the run.

Each physical host performs its own independent complete execution.

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

## Running on Two Physical Hosts

The replication procedure is conceptually:

```text
                     Frozen experiment
                            |
                +-----------+-----------+
                |                       |
                v                       v
        Physical Host A         Physical Host B
                |                       |
                v                       v
       Complete 4-dataset      Complete 4-dataset
           execution               execution
                |                       |
                v                       v
        Host A artifacts        Host B artifacts
                |                       |
                +-----------+-----------+
                            |
                            v
                 Post-hoc cross-host
                      comparison
```

The same experimental methodology is used on both hosts.

The two host executions remain independent. Their result directories are
compared only after the definitive executions have been completed.

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
288 matched conditions per dataset
1,152 matched conditions across four datasets
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

## Experimental Scale

For one dataset, the definitive timing design contains:

```text
8 machine learning models
x 6 batch sizes
x 6 requested malicious fractions
= 288 experimental conditions
```

Each condition is evaluated using:

```text
30 repetitions
x 12 independent processes
```

Therefore, one dataset produces:

```text
288 conditions
x 30 repetitions
x 12 processes
= 103,680 raw benchmark observations
```

Across four datasets on one physical host:

```text
4 x 103,680
= 414,720 raw benchmark observations
```

Across two physical hosts:

```text
2 x 414,720
= 829,440 raw benchmark observations
```

The complete definitive design therefore comprises:

```text
4 datasets
8 machine learning models
6 batch sizes
6 requested malicious fractions
30 repetitions
12 independent processes
2 physical hosts

829,440 raw benchmark observations
```

---

## Reproducibility and Integrity

The experimental infrastructure is designed so that a definitive result
can be associated with a specific implementation and execution
environment.

Important reproducibility elements include:

- a frozen experiment version;
- independent host executions;
- deterministic dataset-preparation procedures where applicable;
- explicit benchmark configuration;
- warm-up before retained timing measurements;
- repeated measurements;
- independent benchmark processes;
- CPU governor verification;
- host-load gating;
- host monitoring;
- cooldown between dataset executions;
- dataset-level output validation;
- preservation of host metadata;
- preservation of execution logs;
- artifact snapshots;
- SHA-256 integrity information; and
- post-hoc cross-host comparison.

The objective is not to assume that independent machines produce
identical absolute timing values. Instead, the experimental design preserves the
information needed to distinguish absolute performance differences from
the consistency of experimental behavior across environments.

---

## Interpretation of Cross-Host Results

Cross-host measurements should be interpreted carefully.

A difference in absolute latency between Host A and Host B does not, by
itself, indicate a failure of reproducibility. Different physical
systems may execute the same workload at different absolute speeds.

For this reason, the analysis distinguishes between:

```text
Absolute timing behavior
        |
        +--> latency ratios

Relative ordering of matched conditions
        |
        +--> cross-host Spearman rank correlation
```

Latency ratios quantify differences in absolute execution time.

The cross-host Spearman rank correlation evaluates whether matched
experimental conditions retain a similar relative ordering across the
two hosts.

This statistic is separate from the tree-path Spearman analysis defined
in the experimental protocol. Latency ratios and cross-host rank
correlation answer related but different questions and should not be
interpreted as interchangeable.

---

## Repository Entry Points

The principal entry points for the definitive experiment are:

| File | Purpose |
|---|---|
| `run_all_datasets_definitive.sh` | Executes the complete four-dataset definitive experiment on one host |
| `compare_two_hosts.sh` | Runs the manual post-hoc comparison between two complete physical-host executions |
| `scripts/compare_all_hosts.py` | Coordinates cross-host comparison across all four datasets |
| `scripts/compare_hosts.py` | Performs matched-condition cross-host statistical comparison |
| `PROTOCOL.md` | Documents the definitive experimental methodology |

The dataset preparation and experiment implementation are contained in
the corresponding repository scripts and `latency_artifact` components.

---

## Recommended Reproduction Workflow

A complete reproduction follows this sequence:

```text
1. Obtain the repository and required datasets
                |
                v
2. Prepare the execution environment
                |
                v
3. Select and verify the definitive experiment version
                |
                v
4. Execute run_all_datasets_definitive.sh on Host A
                |
                v
5. Preserve Host A result package
                |
                v
6. Execute the same definitive experiment on Host B
                |
                v
7. Preserve Host B result package
                |
                v
8. Make both complete host run directories available
                |
                v
9. Execute compare_two_hosts.sh
                |
                v
10. Inspect dataset-level and aggregate cross-host results
```

Benchmark generation and cross-host comparison are deliberately separate
stages of the workflow.

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

The source datasets are not treated as interchangeable inputs.

Each of the four datasets has its corresponding preparation procedure,
validation logic, and expected source organization.

The definitive evaluation uses:

```text
CICIDS2017
GenIDS-CIC17
GenIDS-UNSW15
GenIDS-CIC18
```

Before starting a definitive run, the required dataset files must be
available in the locations expected by the repository configuration.

Dataset-specific preparation is performed before the common model
training and timing stages.

This separation is intentional:

```text
Dataset-specific source data
            |
            v
Dataset-specific preparation
            |
            v
Common experimental representation
            |
            v
Common training and timing methodology
```

The purpose is to accommodate differences among the source datasets
without changing the core definitive timing methodology for each
dataset.

---

## Repository Structure

The repository separates experimental implementation, configuration,
documentation, execution scripts, and generated results.

A high-level view is:

```text
latency-ids/
├── configs/
├── docs/
├── latency_artifact/
├── results/
├── scripts/
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

## Experimental Infrastructure

The main experimental implementation is contained in:

```text
latency_artifact/
```

Supporting scripts are contained in:

```text
scripts/
```

Experiment configuration is contained in:

```text
configs/
```

The definitive multi-dataset orchestration is provided by:

```text
run_all_datasets_definitive.sh
```

The post-hoc two-host comparison is exposed through:

```text
compare_two_hosts.sh
```

These components have distinct responsibilities.

The definitive runner generates measurements independently on each
physical host, whereas the cross-host wrapper operates only on completed
host results.

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


## Important Interpretation Notes

The definitive experiment is designed to evaluate computational behavior
under controlled experimental conditions.

Several distinctions are important when interpreting the outputs.

### Predictive performance and computational performance

Predictive quality and inference performance represent different aspects
of an ML-IDS.

A model with strong predictive performance is not necessarily the model
with the lowest inference latency or highest throughput.

The experimental methodology therefore preserves computational
measurements independently of predictive metrics.

### Batch latency and per-flow cost

Processing multiple flows in one inference call changes the unit being
measured.

Total batch latency describes the cost of the complete inference call,
whereas per-flow timing distributes that cost across the flows contained
in the batch.

These quantities should not be interpreted as identical.

### Latency and throughput

Latency and throughput are related but distinct.

A configuration may improve throughput by processing more flows per
inference call while still exhibiting a different total call latency.

Both dimensions are therefore retained in the analysis.

### Absolute performance and cross-host consistency

Different physical hosts may produce different absolute timing values.

Cross-host reproducibility should consequently be examined using the
preserved absolute timing information together with the relative
ordering of matched experimental conditions.

The post-hoc cross-host analysis uses Spearman rank correlation for the
latter purpose. This cross-host statistic must not be confused with the
separate tree-path Spearman analysis defined in the experimental
protocol.

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

The two host executions should remain identifiable as independent
experimental runs.

Cross-host analysis outputs should also be preserved separately rather
than replacing either host's original measurements.

---

## Integrity Verification

After transferring a packaged host result, verify its checksum before
using it for subsequent analysis.

For example:

```bash
sha256sum -c multidataset-results-<timestamp>.tar.gz.sha256
```

The expected result is an `OK` verification for the archive.

The internal integrity information contained in the packaged artifact
provides an additional mechanism for auditing the preserved files.

---

## Reproducibility Checklist

Before considering a host execution complete, verify that:

- all four datasets were evaluated;
- the definitive runner completed successfully;
- the expected dataset-level analyses were generated;
- host metadata was preserved;
- benchmark monitoring information was preserved;
- the final package was created;
- the package checksum verifies successfully; and
- the repository revision associated with the execution is known.

Before performing the cross-host comparison, verify that:

- both physical-host executions are complete;
- both executions correspond to the intended experimental methodology;
- all four `timing_summary.csv` files exist for each host; and
- the original host results remain unchanged.

After the comparison, preserve the generated cross-host analysis
alongside the two independent host artifacts.

---

## Quick Reference

### Run the complete experiment on one host

```bash
./run_all_datasets_definitive.sh
```

### Verify a generated result package

```bash
sha256sum -c multidataset-results-<timestamp>.tar.gz.sha256
```

### Compare two complete host executions

```bash
./compare_two_hosts.sh \
    HOST_A_RUN \
    HOST_B_RUN \
    CROSS_HOST_OUTPUT_DIR
```

### Detailed methodology

```text
PROTOCOL.md
```

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

---

<p align="center">
  <strong>Reproducible measurements. Independent hosts. Preserved artifacts.</strong>
</p>
