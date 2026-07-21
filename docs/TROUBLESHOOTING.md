# Troubleshooting

## Docker CLI exists but the daemon is unavailable

Inspect the service first:

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker.service -n 100 --no-pager
```

Then try:

```bash
sudo systemctl restart docker
docker info
```

## `hosts` is specified both as a flag and in `daemon.json`

Ubuntu's systemd unit commonly starts Docker with `-H fd://`. If
`/etc/docker/daemon.json` also contains a `hosts` entry, Docker refuses to
start. Prefer the standard local socket for this artifact: remove the `hosts`
entry from `daemon.json`, validate the JSON, and restart Docker.

```bash
python3 -m json.tool /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info
```

Do not expose an unauthenticated Docker TCP socket such as
`tcp://0.0.0.0:8501`. It grants daemon-level control to reachable clients.

## The selected CPU does not use the `performance` governor

The definitive runner rejects non-performance governors by default because
frequency policy can distort microsecond-scale measurements.

```bash
sudo apt-get install -y linux-tools-common linux-tools-generic
sudo cpupower frequency-set -g performance
```

For a smoke test only, bypass the strict check with
`LADC_STRICT_CONTROLS=0`.

## Host load remains above the accepted limit

The runner waits for load-1 to fall below `LADC_MAX_LOAD1` before timing. Do not
terminate workloads owned by other users. Either move the definitive run to a
quieter host or document the environment as shared workload and use a limit
appropriate to that declared context.

## The corrected dataset is already available locally

Pass the directory containing `monday.csv` through `friday.csv`:

```bash
bash run_definitive_linux.sh /absolute/path/to/CICIDS2017_improved_CNS2022
```

The runner still verifies all five files against the expected SHA-256 hashes.
