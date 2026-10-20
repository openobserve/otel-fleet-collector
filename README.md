# otel-fleet-collector

Container image for [OpenObserve](https://openobserve.ai) Fleet Management.
It runs the OpenTelemetry project's
[`opampsupervisor`](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/cmd/opampsupervisor)
as PID 1, which starts and manages
[`otelcol-contrib`](https://github.com/open-telemetry/opentelemetry-collector-contrib)
as its child process in the same container. OpenObserve sends the collector
configuration over OpAMP.

The image contains **only unmodified upstream binaries**. The
[Dockerfile](Dockerfile) downloads them from
[opentelemetry-collector-releases](https://github.com/open-telemetry/opentelemetry-collector-releases),
checks each one against the upstream `.sha256` file, and copies them onto
`gcr.io/distroless/static-debian13:nonroot`. Nothing else is added.

| Path | Contents |
|---|---|
| `/usr/local/bin/opampsupervisor` | entrypoint |
| `/usr/local/bin/otelcol-contrib` | collector, started by the supervisor |
| `/etc/opampsupervisor/supervisor.yaml` | supervisor config, mounted at runtime (not included in the image) |
| `/var/lib/opampsupervisor` | supervisor state (`VOLUME`); keep it across restarts so the collector keeps its identity |

The image runs as the non-root user `65532`.

## Images and tags

```
o2cr.ai/openobserve/otel-fleet-collector:<version>   # = public.ecr.aws/zinclabs/otel-fleet-collector
ghcr.io/openobserve/otel-fleet-collector:<version>
```

- `<version>` is the upstream version, for example `0.163.1`. Supervisor and
  collector are always the same upstream version.
- `latest` points to the highest version built.
- Images are built for `linux/amd64` and `linux/arm64`.
- A [scheduled workflow](.github/workflows/build.yml) checks upstream every
  6 hours. It builds a version once both release tags exist: `vX.Y.Z` and
  `cmd/opampsupervisor/vX.Y.Z`.

## Run

Write a `supervisor.yaml`. OpenObserve's *Add collector* dialog generates one;
this is the minimal form:

```yaml
server:
  # WebSocket. Use https://... instead (OpAMP over HTTP polling) if a proxy
  # or load balancer between the collector and OpenObserve cannot carry WebSocket.
  endpoint: wss://<openobserve-host>/api/<org>/v1/opamp
  headers:
    Authorization: "Basic <base64 of fleet:<fleet token>>"

capabilities:
  accepts_remote_config: true
  reports_effective_config: true
  reports_health: true
  reports_own_metrics: true
  accepts_restart_command: true
  reports_available_components: true
  # Do not set reports_remote_config: it is deprecated and rejected.

agent:
  executable: /usr/local/bin/otelcol-contrib
  passthrough_logs: true
  env:
    O2_ENDPOINT: https://<openobserve-host>
    O2_TOKEN: <ingestion token>

storage:
  directory: /var/lib/opampsupervisor
```

Then run:

```bash
docker run -d --name otel-fleet-collector \
  -v "$PWD/supervisor.yaml:/etc/opampsupervisor/supervisor.yaml:ro" \
  -v otel-fleet-state:/var/lib/opampsupervisor \
  o2cr.ai/openobserve/otel-fleet-collector:latest
```

The image contains no OpenObserve endpoint or token. Provide them only
through the mounted `supervisor.yaml`; on Kubernetes, mount it from a Secret.

### Stopping

The supervisor is PID 1 and receives `SIGTERM` directly; there is no shell
wrapper. On `SIGTERM` it stops the collector and waits up to 10 seconds before
sending `SIGKILL`. Give the container a stop grace period of **at least 15
seconds**. The Kubernetes default `terminationGracePeriodSeconds: 30` is
enough. `docker stop` waits only 10 seconds by default, so use `docker stop -t 30`.

### Kubernetes

A Helm chart that deploys this image as a DaemonSet will be published separately.
It keeps `/var/lib/opampsupervisor` on a `hostPath` volume so each node's
collector keeps the same identity across pod restarts. A `hostPath` directory
is created owned by root, so the chart must make it writable by uid 65532, or
run the pod as root. Root is often needed anyway to read node log files.

## License

[Apache-2.0](LICENSE). The upstream binaries are Apache-2.0, © The OpenTelemetry Authors.
