#!/usr/bin/env bash
# Helpers for the local k3s-in-Docker cluster.
#   cluster.sh kubeconfig            write .kube/lab.yaml pointing at 127.0.0.1
#                                    (LAB_JOIN_NETWORK=1: running inside a CI job container,
#                                    join the lab network and use the node address instead)
#   cluster.sh wait                  wait until every node is Ready
#   cluster.sh import <image:tag>    load a local image into every node's containerd
#                                    (the same pattern as an air-gapped image drop)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
SERVER="${CLUSTER}-server-1"
KUBECONFIG_OUT="$ROOT/.kube/${CLUSTER}.yaml"
export MSYS_NO_PATHCONV=1
# Native Windows tools (kubectl.exe) need a Windows path; no-op elsewhere.
native_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

nodes() { docker ps --filter "label=lab.example/cluster=${CLUSTER}" --format '{{.Names}}' | sort; }

case "${1:-}" in
  kubeconfig)
    mkdir -p "$(dirname "$KUBECONFIG_OUT")"
    for _ in $(seq 1 60); do
      if docker exec "$SERVER" test -s /etc/rancher/k3s/k3s.yaml 2>/dev/null; then break; fi
      sleep 2
    done
    api="https://127.0.0.1:${API_PORT:-6443}"
    if [[ "${LAB_JOIN_NETWORK:-0}" == "1" ]]; then
      # Inside a CI job container host loopback is unreachable: join the node network.
      docker network connect "${CLUSTER}-net" "$(hostname)" 2>/dev/null || true
      api="https://$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$SERVER"):6443"
    fi
    docker exec "$SERVER" cat /etc/rancher/k3s/k3s.yaml \
      | sed -e "s#https://127.0.0.1:6443#${api}#" -e "s#: default#: ${CLUSTER}#" \
      > "$KUBECONFIG_OUT"
    chmod 600 "$KUBECONFIG_OUT"
    echo "$KUBECONFIG_OUT"
    ;;
  wait)
    kc="$(native_path "$KUBECONFIG_OUT")"
    want="$(nodes | wc -l)"
    for _ in $(seq 1 90); do
      ready="$(kubectl --kubeconfig "$kc" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l || true)"
      if [[ "$ready" -ge "$want" && "$want" -gt 0 ]]; then
        kubectl --kubeconfig "$kc" get nodes -o wide
        exit 0
      fi
      sleep 2
    done
    echo "timed out waiting for $want Ready nodes" >&2
    kubectl --kubeconfig "$kc" get nodes >&2 || true
    exit 1
    ;;
  import)
    image="${2:?usage: cluster.sh import <image:tag>}"
    for n in $(nodes); do
      docker save "$image" | docker exec -i "$n" ctr -n k8s.io images import --digests - >/dev/null
      echo "imported $image into $n"
    done
    ;;
  *)
    sed -n '2,7p' "$0"; exit 2 ;;
esac
