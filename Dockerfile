# syntax=docker/dockerfile:1
#
# OpenObserve Fleet Management collector image.
#
# Repackages two unmodified upstream release binaries from
# github.com/open-telemetry/opentelemetry-collector-releases:
#   - opampsupervisor  (runs as PID 1)
#   - otelcol-contrib  (started and stopped by the supervisor as its child)
#
# Build: docker buildx build --platform linux/amd64,linux/arm64 --build-arg VERSION=0.163.1 .

ARG VERSION

# Download stage runs on the build host's platform; it only fetches and
# verifies files for the target architecture, so no emulation is needed.
FROM --platform=$BUILDPLATFORM alpine:3.23 AS fetch
ARG VERSION
ARG TARGETARCH
WORKDIR /work
RUN set -eu; \
    if [ -z "${VERSION}" ]; then echo "ERROR: --build-arg VERSION=X.Y.Z is required" >&2; exit 1; fi; \
    base="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download"; \
    sup="opampsupervisor_${VERSION}_linux_${TARGETARCH}"; \
    col="otelcol-contrib_${VERSION}_linux_${TARGETARCH}.tar.gz"; \
    wget -q -O "${sup}"        "${base}/cmd/opampsupervisor/v${VERSION}/${sup}"; \
    wget -q -O "${sup}.sha256" "${base}/cmd/opampsupervisor/v${VERSION}/${sup}.sha256"; \
    wget -q -O "${col}"        "${base}/v${VERSION}/${col}"; \
    wget -q -O "${col}.sha256" "${base}/v${VERSION}/${col}.sha256"; \
    for f in "${sup}" "${col}"; do \
      want="$(awk '{print $1; exit}' "${f}.sha256")"; \
      if ! echo "${want}  ${f}" | sha256sum -c -; then \
        echo "ERROR: sha256 mismatch for ${f}: expected '${want}', got '$(sha256sum "${f}" | awk '{print $1}')'" >&2; \
        exit 1; \
      fi; \
    done; \
    tar -xzf "${col}" otelcol-contrib; \
    mkdir -p /out/bin /out/storage; \
    install -m 0755 "${sup}" /out/bin/opampsupervisor; \
    install -m 0755 otelcol-contrib /out/bin/otelcol-contrib

# Final image: distroless "static" (nonroot). Both upstream binaries are
# statically linked Go programs, so no libc is needed. The base provides CA
# certificates (for wss:// / https:// to OpenObserve and exporters), tzdata and
# a nonroot user (65532), and has no shell or package manager.
FROM gcr.io/distroless/static-debian13:nonroot
ARG VERSION
LABEL org.opencontainers.image.title="otel-fleet-collector" \
      org.opencontainers.image.description="Upstream opampsupervisor (PID 1) + otelcol-contrib, repackaged unchanged for OpenObserve Fleet Management" \
      org.opencontainers.image.source="https://github.com/openobserve/otel-fleet-collector" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.vendor="OpenObserve" \
      org.opencontainers.image.version="${VERSION}"

COPY --from=fetch /out/bin/opampsupervisor /out/bin/otelcol-contrib /usr/local/bin/
COPY --from=fetch --chown=65532:65532 /out/storage /var/lib/opampsupervisor

USER 65532:65532
VOLUME ["/var/lib/opampsupervisor"]

# Exec form, no shell: the supervisor is PID 1 and receives SIGTERM directly.
# On SIGTERM it stops the collector (SIGTERM, then SIGKILL after 10s), so the
# container needs a stop grace period of at least ~15s; the Kubernetes default
# of 30s is enough. Do not lower terminationGracePeriodSeconds below 15.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/opampsupervisor"]
CMD ["--config", "/etc/opampsupervisor/supervisor.yaml"]
