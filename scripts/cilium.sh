#!/usr/bin/env bash
# Cilium on the k3s-in-Docker cluster (requires `cni = "cilium"` in Terraform).
#   cilium.sh install   prepare node mounts, install Cilium + Hubble, wait for nodes Ready
#   cilium.sh verify    agent health, and Hubble shows a policy DROP for a blocked probe
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
kc="$ROOT/.kube/${CLUSTER}.yaml"
if command -v cygpath >/dev/null 2>&1; then kc="$(cygpath -w "$kc")"; fi
k() { kubectl --kubeconfig "$kc" "$@"; }
nodes() { docker ps --filter "label=lab.example/cluster=${CLUSTER}" --format '{{.Names}}' | sort; }

prepare_nodes() {
  # Real VMs have these already. Inside node containers they must be mounted, and made
  # shared, because Cilium mounts them into its pods with mount propagation.
  for n in $(nodes); do
    docker exec "$n" sh -c '
      # /run and /var/run are private tmpfs mounts in the node container; Cilium mounts
      # /var/run/netns with propagation, so the whole tree must be shared.
      mount --make-rshared /
      mountpoint -q /sys/fs/bpf || mount -t bpf bpffs /sys/fs/bpf
      mount --make-shared /sys/fs/bpf
      mkdir -p /run/cilium/cgroupv2
      mountpoint -q /run/cilium/cgroupv2 || mount -t cgroup2 none /run/cilium/cgroupv2
      mount --make-shared /run/cilium/cgroupv2
    '
    echo "prepared $n"
  done
}

install() {
  prepare_nodes
  # shellcheck disable=SC2046
  "$ROOT/scripts/helm.sh" upgrade --install cilium $("$ROOT/scripts/charts.sh" ref cilium) \
    -n kube-system -f kubernetes/cilium/values.yaml --wait --timeout 10m
  k -n kube-system rollout status ds/cilium --timeout=300s
  "$ROOT/scripts/cluster.sh" wait
}

verify() {
  local fail=0
  # Every agent reports itself healthy.
  for p in $(k -n kube-system get pods -l k8s-app=cilium -o name); do
    if k -n kube-system exec "$p" -c cilium-agent -- cilium-dbg status --brief >/dev/null 2>&1; then
      echo "PASS  $p healthy"
    else
      echo "FAIL  $p unhealthy"; fail=1
    fi
  done

  # Blocked probe from an unlisted namespace, then ask Hubble on the target node for the drop.
  k delete pod hubble-probe -n default --ignore-not-found --wait=true >/dev/null
  k run hubble-probe -n default --image=busybox:1.36 --restart=Never --command -- \
    wget -q -T 3 -O- http://demo-app.demo.svc.cluster.local:9090/healthz >/dev/null
  k wait -n default --for=jsonpath='{.status.phase}'=Failed pod/hubble-probe --timeout=60s >/dev/null 2>&1 || true
  local drops=""
  for p in $(k -n kube-system get pods -l k8s-app=cilium -o name); do
    drops+="$(k -n kube-system exec "$p" -c cilium-agent -- \
      hubble observe --last 500 --verdict DROPPED --from-pod default/hubble-probe -o compact 2>/dev/null || true)"
  done
  k delete pod hubble-probe -n default --ignore-not-found --wait=false >/dev/null
  if [[ "$drops" == *"Policy denied"* || "$drops" == *"DROPPED"* ]]; then
    echo "PASS  Hubble recorded the policy drop:"
    grep -m2 -E 'DROPPED' <<<"$drops" | sed 's/^/      /'
  else
    echo "FAIL  no DROPPED flow for default/hubble-probe in Hubble"; fail=1
  fi
  return $fail
}

case "${1:-}" in
  install) install ;;
  verify) verify ;;
  *) sed -n '2,4p' "$0"; exit 2 ;;
esac
