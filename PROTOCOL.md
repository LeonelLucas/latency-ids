# Experimental protocol

## Objective

The experiment separates predictive usefulness from computational serving
behavior. A model must first produce meaningful scores and decisions on a
temporally disjoint test set. The fitted model is then treated as a serving
component whose call size and input composition are controlled.

## Dataset partitions

The corrected CNS2022 release of CICIDS2017 is split before sampling:

- Monday-Wednesday: training;
- Thursday: validation;
- Friday: testing and timing.

The split prevents flow overlap across stages and exposes models to attack
families that are absent from the training partition. IP addresses, flow and
row identifiers, timestamps, labels, and `Attempted Category` are excluded,
leaving 84 numeric predictive attributes.

## Predictive evaluation

The artifact trains logistic regression, SGD with logistic loss, Gaussian
Naive Bayes, decision tree, random forest, gradient boosting, AdaBoost, and an
MLP. It reports precision, recall, F1, false-positive rate, MCC, average
precision, ROC-AUC, and secondary accuracy. Threshold sensitivity selects the
MCC-maximizing threshold on validation and freezes it before test evaluation.
Test scenarios use 1%, 5%, 10%, and 50% malicious prevalence.

## Timing factors and hierarchy

- Call size: 1, 8, 16, 32, 64, and 100 flows per `predict` call.
- Requested malicious fraction: 0%, 1%, 5%, 10%, 50%, and 100%.
- Eight classifiers.
- Thirty timed calls per classifier/call-size/composition condition.
- Twelve fresh, sequential process runs on each host.
- Two physical Linux hosts.

One host contains 288 conditions. One process executes all 288 conditions in a
new randomized and interleaved order, with 30 calls per condition. The process
then writes its raw file and exits before the next process begins.

For mixed inputs, the malicious count is drawn from a binomial distribution.
The requested and realized fractions are both retained. This represents small
fractions in expectation when an individual small matrix cannot contain the
exact requested proportion.

## Warm-up and timed boundary

Within every fresh process, each model receives 20 untimed calls at call size 1
and another 20 at call size 100, using a requested malicious fraction of 50%.
This exercises the two serving extremes before measurement. It does not measure
model loading or first-call latency.

Each raw timing observation covers one complete `Pipeline.predict` call on a
ready `b x 84` NumPy matrix. It includes fitted transformations inside the
pipeline and excludes data parsing, flow extraction, queueing, and batch
formation.

## Outcomes

The operational outcomes for every call are total call latency, latency per
flow, and throughput. For each condition, the 360 calls across 12 processes are
described using mean, standard deviation, median, p95, and p99. The percentiles
are tail summaries of latency, not additional measured outcomes.

## Confirmatory class-composition analysis

For each classifier and call size, the 30 benign-only calls are averaged within
each process and paired with the mean of the 30 malicious-only calls from the
same process. Twelve process runs therefore produce 12 paired differences.

A two-sided exact sign-flip test uses the process runs as independent blocks.
Benjamini-Hochberg correction is applied across the 48 classifier-by-call-size
comparisons. Results include the paired difference, a 95% confidence interval,
and paired Cohen's dz. An effect is confirmatory only if it passes correction on
both hosts and has the same direction.

Twelve process runs give the exact two-sided sign-flip test sufficient p-value
resolution for the 48-test correction while keeping the definitive experiment
feasible. Repeated calls within a process are never treated as independent
runtime instances.

## Cross-host analysis

Spearman correlation compares the 288 matched condition medians. The analysis
also reports the coefficient of variation among process medians and the
p99-to-median ratio. Absolute latency is hardware-dependent; replicated
ordering and same-direction class effects provide the robustness evidence.
