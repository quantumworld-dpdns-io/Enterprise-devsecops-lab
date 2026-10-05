#!/usr/bin/env bash
# Security VM stack: Wazuh single-node (manager, indexer, dashboard) from the official,
# pinned wazuh-docker release, plus agent enrolment for the lab hosts.
#
#   wazuh.sh fetch    download wazuh-docker at $WAZUH_VERSION into .kube/wazuh-docker
#   wazuh.sh up       generate TLS certificates, start the stack (needs ~4 GB RAM and
#                     vm.max_map_count >= 262144 on the Docker host, see below)
#   wazuh.sh config   validate the compose file without starting anything
#   wazuh.sh down     stop and delete the stack and its volumes
#
# Why fetch instead of vendoring: the upstream deployment ships certificate tooling and
# indexer/dashboard configuration that changes between releases. Pinning the release tag
# keeps it reproducible without copying (and then silently diverging from) upstream files.
#
# In the VM-based lab this stack runs on sec-vm-1 (192.168.100.10, security VLAN). Agents on
# the management VLAN enrol through the firewall on 1514/1515 only.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WAZUH_VERSION="${WAZUH_VERSION:-v4.14.8}"
DEST="$ROOT/.kube/wazuh-docker-${WAZUH_VERSION}"
SN="$DEST/single-node"
CURL="${CURL:-curl}"
read -r -a CURL_OPTS <<<"${CURL_OPTS:-}"

fetch() {
  [[ -d "$SN" ]] && { echo "cached $WAZUH_VERSION"; return; }
  mkdir -p "$DEST"
  "$CURL" "${CURL_OPTS[@]}" -fsSL "https://github.com/wazuh/wazuh-docker/archive/refs/tags/${WAZUH_VERSION}.tar.gz" \
    | tar -xz -C "$DEST" --strip-components=1
  echo "fetched wazuh-docker $WAZUH_VERSION"
}

case "${1:-}" in
  fetch) fetch ;;
  config)
    fetch
    docker compose -f "$SN/docker-compose.yml" config -q && echo "wazuh compose config valid ($WAZUH_VERSION)"
    ;;
  up)
    fetch
    # The indexer (OpenSearch) refuses to start below this kernel limit.
    # Linux host:  sudo sysctl -w vm.max_map_count=262144
    # Docker Desktop (WSL2): wsl -d docker-desktop sysctl -w vm.max_map_count=262144
    current="$(docker run --rm alpine:3.20 cat /proc/sys/vm/max_map_count)"
    if (( current < 262144 )); then
      echo "vm.max_map_count is $current on the Docker host; raise it to 262144 first (see comments)." >&2
      exit 1
    fi
    docker compose -f "$SN/generate-indexer-certs.yml" run --rm generator
    docker compose -f "$SN/docker-compose.yml" up -d
    echo "Wazuh dashboard: https://127.0.0.1:443 (default credentials are in the upstream README; change them)"
    ;;
  down) docker compose -f "$SN/docker-compose.yml" down -v ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
