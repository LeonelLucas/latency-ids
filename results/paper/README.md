# Paper result bundles

This directory contains the compact definitive outputs used in the paper.

- `host-lc`: low-contention environment, Intel Core i7-3770.
- `host-sw`: shared-workload environment, Intel Xeon E-2224G.

Each bundle includes call-level timing observations, predictive scores and
metrics, condition summaries, class-effect tests, figures, host telemetry,
execution logs, validation reports, and hashes for reproducible files omitted
because of size.

The labels describe the observed execution context, not hardware quality.
Host-SW has the newer and faster processor but was subject to a shared software
workload; Host-LC used older hardware under lower contention.

The directories retain the original validated outputs. Do not edit the CSV or
metadata files in place. Derived analyses should write to a separate directory
and record the source commit.
