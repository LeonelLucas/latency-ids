# Experimental protocol

## Objective

The experiment evaluates predictive performance and computational serving
behavior in machine-learning-based intrusion detection systems (ML-IDS).

Predictive evaluation and runtime benchmarking are treated as distinct stages.
A model is first trained, validated, and evaluated using temporally separated
data. The fitted model is then treated as a serving component whose call size
and input composition are experimentally controlled.

The complete experimental design comprises four independent datasets and is
replicated on two physical Linux hosts. Each dataset is prepared, trained,
evaluated, benchmarked, and analyzed independently. Models, prepared samples,
and benchmark observations are never shared between datasets.

## Datasets

The definitive experiment uses four datasets:

- CICIDS2017, using the CNS2022 corrected release;
- GenIDS-CIC17;
- GenIDS-UNSW15;
- GenIDS-CIC18.

CICIDS2017 uses its ordered schema of 84 numeric ML features after removal of
identifiers, timestamps, labels, and other non-predictive metadata defined by
the preparation pipeline.

The three GenIDS datasets use a common ordered schema of 63 ML features. The
schema was harmonized across GenIDS-CIC17, GenIDS-UNSW15, and GenIDS-CIC18 so
that the same feature names and ordering are used in all three experiments.

The GenIDS schema retains source and destination ports, protocol, IP version,
VLAN ID, and tunnel ID.

The 84-feature CICIDS2017 schema and the 63-feature GenIDS schema are not
forced to be identical. Each dataset remains an independent experiment.

## Temporal partitioning

All datasets are partitioned temporally before the final class-balanced
sampling used to construct the experiment partitions.

### CICIDS2017

The corrected CICIDS2017 release is partitioned by day:

- Monday-Wednesday: training;
- Thursday: validation;
- Friday: testing and runtime benchmarking.

Training and test partitions are sampled up to 100,000 observations per class.
Validation is sampled up to 25,000 observations per class.

### GenIDS-CIC17

GenIDS-CIC17 is partitioned using its `date` field:

- 2017-07-03 through 2017-07-05: training;
- 2017-07-06: validation;
- 2017-07-07: testing and runtime benchmarking.

Training and test partitions are sampled up to 100,000 observations per class.
Validation is sampled up to 25,000 observations per class.

### GenIDS-UNSW15

GenIDS-UNSW15 is partitioned using its `date` field:

- 2015-01-22: training;
- 2015-01-23: validation;
- 2015-02-18: testing and runtime benchmarking.

Training and test partitions are sampled up to 100,000 observations per class.
Validation is sampled up to 25,000 observations per class.

### GenIDS-CIC18

GenIDS-CIC18 does not use a derived calendar-date field for partitioning.
Instead, observations are stably ordered by
`bidirectional_first_seen_ms`.

The ordered dataset is divided temporally as follows:

- first 40%: training;
- next 8%: validation;
- remaining 52%: testing and runtime benchmarking.

After temporal partitioning, training and test partitions are sampled up to
100,000 observations per class, while validation is sampled up to 25,000
observations per class.

The timestamp used for temporal ordering is not supplied to the classifiers as
an ML feature.

## Models

Eight classifiers are evaluated independently for every dataset:

- logistic regression (LoR);
- stochastic gradient descent with logistic loss (SGD);
- Gaussian Naive Bayes (NB);
- decision tree (DT);
- random forest (RF);
- gradient boosting (GB);
- AdaBoost (AB);
- multilayer perceptron (MLP).

Models fitted for one dataset are never reused for another dataset.

## Predictive evaluation

Predictive evaluation is performed before runtime benchmarking.

The evaluation reports precision, recall, F1, false-positive rate, Matthews
correlation coefficient (MCC), average precision, ROC-AUC, and secondary
accuracy.

Threshold sensitivity is evaluated using the validation partition. The
MCC-maximizing threshold is selected from validation data and frozen before
test evaluation.

Test scenarios evaluate requested malicious prevalences of:

- 1%;
- 5%;
- 10%;
- 50%.

This stage evaluates predictive behavior independently from the runtime timing
experiment.

## Runtime benchmark

The benchmark controls three experimental factors:

- classifier: 8 levels;
- call size: 1, 8, 16, 32, 64, and 100 flows;
- requested malicious fraction: 0%, 1%, 5%, 10%, 50%, and 100%.

This produces:

8 classifiers x 6 call sizes x 6 class compositions = 288 conditions.

Each condition receives 30 timed calls within each fresh benchmark process.

Therefore, one process produces:

288 conditions x 30 repetitions = 8,640 raw timing observations.

The complete benchmark uses 12 fresh sequential process runs per dataset on
each host.

Consequently, one dataset produces:

8,640 observations x 12 processes = 103,680 raw benchmark observations.

The four datasets therefore produce:

4 x 103,680 = 414,720 raw benchmark observations per host.

The complete two-host replication produces:

2 x 414,720 = 829,440 raw benchmark observations.

## Independent process runs

The 12 benchmark process runs are the independent runtime blocks used by the
experiment.

Each process executes all 288 benchmark conditions. The conditions are
randomized and interleaved in a new order for each process. Each condition
contains 30 timed calls.

After completing its benchmark workload, the process writes its raw result
file and exits before the next process begins.

Repeated calls within one process are repeated measurements and are not treated
as independent runtime instances in confirmatory inference.

## Randomization and input composition

Benchmark tasks are randomized and interleaved to reduce systematic ordering
effects.

For mixed inputs, the number of malicious observations in an individual call
is sampled according to the requested malicious fraction. The requested and
realized malicious fractions are both retained in the raw benchmark output.

This is particularly important for small call sizes, where an exact requested
fraction may not be representable within every individual matrix.

Pure benign and pure malicious conditions use requested fractions of 0% and
100%, respectively.

## Warm-up

Within each fresh benchmark process, every fitted model receives untimed
warm-up calls before timed measurements begin.

Warm-up exercises the minimum and maximum benchmark call sizes:

- call size 1;
- call size 100.

Each extreme receives 20 untimed calls using a requested malicious fraction of
50%.

Warm-up is excluded from the raw timing observations. The experiment therefore
does not measure model loading or first-call latency.

## Timing boundary

Each raw timing observation covers one complete `Pipeline.predict` call on an
already prepared NumPy input matrix.

CICIDS2017 prediction matrices contain 84 ML features.

GenIDS-CIC17, GenIDS-UNSW15, and GenIDS-CIC18 prediction matrices contain 63
ML features.

The measured interval includes fitted transformations executed inside the
pipeline and the classifier prediction itself.

It excludes dataset parsing, flow extraction, temporal partitioning, sampling,
queueing, batch formation, model loading, and experiment orchestration.

The benchmark therefore measures inference-serving behavior rather than
end-to-end network-monitoring latency.

## Runtime outcomes

Every timed call records:

- total call latency;
- latency per flow;
- throughput in flows per second;
- requested malicious fraction;
- realized malicious fraction;
- process identifier;
- repetition and execution sequence.

For tree-based models, the benchmark may additionally record mean tree-path
nodes for the corresponding prediction input.

For each of the 288 conditions, the 30 calls from each of the 12 processes
produce 360 timing observations per host.

Condition summaries report:

- mean total latency;
- mean latency per flow;
- median latency per flow;
- standard deviation of latency per flow;
- p95 latency per flow;
- p99 latency per flow;
- mean throughput.

The percentiles summarize the latency distribution and are not additional
independent outcomes.

## Confirmatory class-composition analysis

The confirmatory class-composition analysis compares pure benign and pure
malicious inputs.

For every classifier and call size, the 30 benign-only calls are first averaged
within each process. The 30 malicious-only calls are independently averaged
within the same process.

The resulting process-level means are paired, producing 12 independent paired
differences for every classifier-by-call-size comparison.

The difference is defined as:

benign mean latency per flow - malicious mean latency per flow.

A two-sided exact sign-flip test is applied to the 12 process-level paired
differences.

Benjamini-Hochberg correction is applied across the 48
classifier-by-call-size comparisons:

8 classifiers x 6 call sizes = 48 comparisons.

The analysis also reports:

- mean benign latency per flow;
- mean malicious latency per flow;
- paired mean difference;
- 95% confidence interval;
- paired Cohen's dz;
- raw sign-flip p-value;
- Benjamini-Hochberg-adjusted p-value.

The same analysis is performed independently on each host.

Cross-host robustness of a class-composition effect is assessed only after both
host executions are available. A replicated effect requires compatible
direction across hosts together with the predefined inferential criteria.

## Tree-path analysis

Tree-path behavior is analyzed separately from the cross-host replication.

For observations with call size 1 and available tree-path information, the
analysis relates latency per flow to mean tree-path nodes.

For each eligible model with sufficient path-length variation, Spearman rank
correlation is calculated between:

- `us_per_flow`;
- `mean_tree_path_nodes`.

This analysis investigates whether prediction path complexity is associated
with inference latency for tree-based models.

This Spearman analysis must not be interpreted as the cross-host comparison.

## Host controls

The definitive experiment is executed on Linux using Docker.

For each execution, the runner selects one logical CPU. By default, the last
online logical CPU is selected, although `TRADEOFF_CPU` may explicitly select
another CPU.

The runner verifies that the selected logical CPU exists and is online.

Experiment containers are restricted to the selected logical CPU using
Docker `--cpuset-cpus`.

Before experimental execution, the runner requires the selected CPU to use the
`performance` frequency governor.

Before each benchmark, the runner waits until host load is below the configured
threshold. A cooldown interval separates training from runtime benchmarking.

Host state is captured immediately before and after benchmark execution.
During the benchmark, the runner periodically records host load, CPU
frequency, and available temperature information.

Containers execute without network access and use the same experiment image
within a host execution.

These controls reduce avoidable environmental variation but do not imply that
absolute latency is hardware-independent.

## Cross-host replication

The complete four-dataset experiment is executed independently on two physical
Linux hosts.

Each host runs the same experimental workflow and produces an independent set
of prepared artifacts, trained models, raw benchmark observations, and
analyses.

The runner operates on one host at a time. It does not coordinate or execute
both machines simultaneously.

Each host produces 103,680 raw benchmark observations per dataset and 414,720
observations across all four datasets.

Across both hosts, the definitive design therefore contains 829,440 raw
benchmark observations.

Cross-host comparison is performed only after both complete host executions
are available.

The comparison operates on matched experimental conditions identified by
dataset, classifier, call size, and requested malicious fraction. Absolute
latency differences are interpreted as hardware-dependent.

Cross-host analysis is distinct from the tree-path Spearman analysis. The
latter relates tree-path complexity to latency within benchmark results,
whereas cross-host analysis evaluates whether experimental behavior is
replicated across physical machines.

The exact final cross-host summary statistics must remain consistent with the
implemented comparison procedure used after both host result sets are
available.

## Reproducibility and output validation

Each dataset produces its own processed data, trained models, predictive
metrics, benchmark raw files, timing summaries, and analysis outputs.

The definitive runner validates the expected feature count for every dataset:

- CICIDS2017: 84;
- GenIDS-CIC17: 63;
- GenIDS-UNSW15: 63;
- GenIDS-CIC18: 63.

For every dataset, final validation additionally requires:

- 12 benchmark raw CSV files;
- 8,640 timing observations in each raw process file;
- 103,680 total raw benchmark observations;
- 288 timing-summary conditions;
- all eight expected classifiers;
- call sizes 1, 8, 16, 32, 64, and 100;
- requested malicious fractions 0%, 1%, 5%, 10%, 50%, and 100%;
- 360 observations per summarized condition;
- 12 contributing process runs per summarized condition.

The runner also preserves experiment logs and host-control information so that
the execution environment and experimental sequence can be audited.
