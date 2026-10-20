#!/usr/bin/env bash
# Prints, in ascending order, every upstream version X.Y.Z (>= MIN_VERSION)
# that is ready to build: both the collector release "vX.Y.Z" and the
# supervisor release "cmd/opampsupervisor/vX.Y.Z" exist and carry the
# linux amd64/arm64 binaries and their .sha256 files.
#
# Usage: upstream-versions.sh [MIN_VERSION]      (needs gh and jq, GH_TOKEN set)
set -euo pipefail

UPSTREAM="${UPSTREAM:-open-telemetry/opentelemetry-collector-releases}"
MIN_VERSION="${1:-0.0.0}"

ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

has_assets() { # <tag> <asset>...
  local names
  names="$(gh api "repos/${UPSTREAM}/releases/tags/$1" --jq '.assets[].name' 2>/dev/null)" || return 1
  shift
  for a in "$@"; do
    grep -qxF "$a" <<<"$names" || return 1
  done
}

ready() { # <version>
  local v="$1"
  has_assets "v${v}" \
    "otelcol-contrib_${v}_linux_amd64.tar.gz" "otelcol-contrib_${v}_linux_amd64.tar.gz.sha256" \
    "otelcol-contrib_${v}_linux_arm64.tar.gz" "otelcol-contrib_${v}_linux_arm64.tar.gz.sha256" &&
  has_assets "cmd/opampsupervisor/v${v}" \
    "opampsupervisor_${v}_linux_amd64" "opampsupervisor_${v}_linux_amd64.sha256" \
    "opampsupervisor_${v}_linux_arm64" "opampsupervisor_${v}_linux_arm64.sha256"
}

tags() { # <ref prefix> -> X.Y.Z list (stable versions only)
  gh api "repos/${UPSTREAM}/git/matching-refs/tags/$1" --jq '.[].ref' |
    sed -n "s#^refs/tags/$1\([0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\)\$#\1#p"
}

# Versions tagged for both the collector and the supervisor.
comm -12 <(tags "v" | sort -u) <(tags "cmd/opampsupervisor/v" | sort -u) | sort -V |
  while read -r v; do
    if ge "$v" "$MIN_VERSION" && ready "$v"; then
      echo "$v"
    fi
  done
