# Troubleshooting

This document covers common environment and execution issues that may
occur when running the definitive multi-dataset experiment.

The main entry point for the definitive experiment is:

```bash
./run_all_datasets_definitive.sh
```

The runner executes the four datasets sequentially under the common
experimental methodology:

1. CICIDS2017
2. GenIDS-CIC17
3. GenIDS-UNSW15
4. GenIDS-CIC18

---

## Docker CLI exists but the daemon is unavailable

Inspect the Docker service first:

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker.service -n 100 --no-pager
```

Then try:

```bash
sudo systemctl restart docker
docker info
```

The definitive experiment requires the Docker daemon to be available
before execution begins.

---

## `hosts` is specified both as a flag and in `daemon.json`

Ubuntu systemd units commonly start Docker with `-H fd://`.

If `/etc/docker/daemon.json` also contains a `hosts` entry, Docker may
refuse to start because the daemon receives conflicting host
configuration.

Prefer the standard local Docker socket. Remove the conflicting `hosts`
entry from `daemon.json`, validate the JSON, and restart Docker:

```bash
python3 -m json.tool /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info
```

Do not expose an unauthenticated Docker TCP socket such as
`tcp://0.0.0.0:8501`. Such a socket can grant daemon-level control to
reachable clients.

---

## The selected CPU does not use the `performance` governor

The definitive runner verifies the governor of the logical CPU selected
for the timing experiment.

The selected CPU can be overridden through `TRADEOFF_CPU`. If this
variable is not set, the definitive runner selects the last logical CPU
available on the host.

The selected CPU must use the `performance` governor. This requirement
reduces variability caused by dynamic CPU frequency policies during
latency measurements.

Check the governor with:

```bash
ONLINE_CPUS="$(getconf _NPROCESSORS_ONLN)"
DEFAULT_CPU="$(( ONLINE_CPUS - 1 ))"
CPU="${TRADEOFF_CPU:-$DEFAULT_CPU}"
cat "/sys/devices/system/cpu/cpu${CPU}/cpufreq/scaling_governor"
```

The expected output is:

```text
performance
```

If necessary, configure the host before running the definitive
experiment. For example, on systems using `cpupower`:

```bash
sudo apt-get install -y linux-tools-common linux-tools-generic
sudo cpupower frequency-set -g performance
```

Verify the governor again before starting the experiment.

The definitive runner stops if the selected CPU does not use the
`performance` governor.

---

## Host load remains above the accepted limit

Before each dataset benchmark, the runner waits until the host satisfies
the quiet-host load criterion.

The default maximum one-minute load average is controlled by
`TRADEOFF_MAX_LOAD1` and is set to `0.50`.

The default maximum waiting period is controlled by
`TRADEOFF_QUIET_WAIT_SECONDS` and is set to `300` seconds.

The runner checks `/proc/loadavg` and starts the corresponding benchmark
only after the one-minute load average is at or below the configured
limit.

If the host remains above the accepted limit, do not terminate workloads
owned by other users merely to satisfy the benchmark condition.

Instead, wait for the host to become quieter or execute the definitive
experiment during a period with lower competing workload.

The accepted load and timestamp are recorded with the experiment
artifacts.

---

## Dataset files are stored in a different location

The definitive runner uses dataset paths that can be configured through
environment variables.

The default locations are relative to the repository and point to the
dataset directory outside the repository.

If the datasets are stored elsewhere, configure the corresponding
dataset path variables before starting the experiment rather than
modifying the experimental code.

Consult `README.md` and the configuration section of
`run_all_datasets_definitive.sh` for the dataset path variables used by
the definitive runner.

This keeps machine-specific filesystem paths separate from the
experimental implementation.

---

## One of the required datasets is unavailable

The definitive experiment evaluates all four datasets:

```text
CICIDS2017
GenIDS-CIC17
GenIDS-UNSW15
GenIDS-CIC18
```

Verify that the required source data are available before beginning the
complete run.

Do not silently substitute a different dataset version or modify the
dataset preparation procedure during a definitive execution.

Dataset-specific preparation is intentionally separated from the common
timing methodology.

---

## The host becomes busy after the experiment starts

Passing the quiet-host gate establishes that the host satisfied the load
criterion before the corresponding benchmark began.

The runner also records host information during execution so that the
environment can be inspected afterward.

Host monitoring includes load information and, when available, the
selected CPU frequency and thermal information.

If substantial external workload occurs during a definitive run, retain
the generated monitoring information and evaluate the affected execution
before using its measurements in the final analysis.

---

## The experiment was interrupted

Do not combine measurements from an incomplete execution with a
different definitive run as though they belonged to the same execution.

Preserve partial artifacts for diagnosis if necessary, then perform a
new complete definitive execution under the frozen experimental
configuration.

Each complete host execution should remain identifiable as an
independent experimental run.

---

## Results were generated successfully

After the complete multi-dataset execution, preserve the generated
result package together with its SHA-256 checksum.

Verify the package using its accompanying checksum file before copying
or analyzing it.

For example:

```bash
sha256sum -c multidataset-results-<timestamp>.tar.gz.sha256
```

A successful verification reports `OK`.

Keep the original result package unchanged after verification.

---

## Comparing the two physical hosts

The complete four-dataset experiment is executed independently on two
physical Linux hosts.

Cross-host comparison is performed only after the definitive executions
from both hosts are available.

The comparison entry point is:

```bash
./compare_two_hosts.sh HOST_A_RUN HOST_B_RUN [OUTPUT_DIR]
```

Do not merge the raw result directories from the two hosts.

The post-hoc comparison pairs equivalent experimental conditions from
the two independent executions and evaluates both absolute timing
differences and the consistency of their relative ordering.

Latency ratios characterize differences in absolute execution time,
while Spearman rank correlation is used to evaluate rank consistency
across equivalent experimental conditions.

These measurements answer different questions: similar rank ordering
does not imply identical absolute latency between physical hosts.

---

## Reproducibility

For a definitive replication, preserve the experimental configuration
used by the frozen experiment.

The definitive experimental code was frozen at commit:

```text
4aa3f0929aba5f5561c1bed15a0a159b42feebb2
```

Later documentation-only commits do not redefine the experimental
configuration used for the definitive measurements.

When reproducing the experiment on another host, use the same frozen
experimental implementation and preserve the generated provenance,
monitoring, result, and checksum artifacts.
