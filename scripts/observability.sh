#!/usr/bin/env bash
# Install or verify the observability stack (umbrella chart kubernetes/helm/observability-stack).
#   observability.sh install   one Helm release "obs" in namespace monitoring
#   observability.sh verify    metrics, logs and traces from demo-app actually arrive
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
kc="$ROOT/.kube/${CLUSTER}.yaml"
if command -v cygpath >/dev/null 2>&1; then kc="$(cygpath -w "$kc")"; fi
k() { kubectl --kubeconfig "$kc" "$@"; }
CHART=kubernetes/helm/observability-stack

install() {
  k create namespace monitoring --dry-run=client -o yaml | k apply -f - >/dev/null
  # Grafana admin password: generated once, stored only in the cluster. Kept out of the
  # chart on purpose: a chart-generated random value changes on every GitOps render.
  if ! k -n monitoring get secret grafana-admin >/dev/null 2>&1; then
    k -n monitoring create secret generic grafana-admin \
      --from-literal=admin-user=admin \
      --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
  fi
  "$ROOT/scripts/charts.sh" vendor "$CHART"
  "$ROOT/scripts/helm.sh" upgrade --install obs "$CHART" -n monitoring --wait --timeout 15m
  echo "Grafana: https://grafana.lab.example:${HTTPS_PORT}  (user admin; password in secret monitoring/grafana-admin)"
}

# Query a monitoring service from inside the cluster with a throwaway curl pod.
incluster() { k -n monitoring run "q-$RANDOM" --rm -i --restart=Never --quiet --image=curlimages/curl:8.11.1 -- -s "$@"; }

verify() {
  local fail=0 up=""
  for _ in $(seq 1 20); do
    curl -sk --resolve "demo.lab.example:${HTTPS_PORT}:127.0.0.1" "https://demo.lab.example:${HTTPS_PORT}/api/v1/work?ms=5" >/dev/null
  done
  sleep 30

  # A new ServiceMonitor takes a config reload plus one scrape interval to show up.
  for _ in $(seq 1 12); do
    up="$(incluster 'http://kps-prometheus.monitoring:9090/api/v1/query?query=up%7Bnamespace%3D%22demo%22%7D%3D%3D1')"
    [[ "$up" == *'"value"'* ]] && break
    sleep 15
  done
  [[ "$up" == *'"value"'* ]] && echo "PASS  Prometheus scrapes demo-app" || { echo "FAIL  no demo-app targets: $up"; fail=1; }

  logs="$(incluster -G 'http://loki.monitoring:3100/loki/api/v1/query_range' --data-urlencode 'query={namespace="demo"}' --data-urlencode 'limit=5')"
  [[ "$logs" == *'"values"'* && "$logs" != *'"result":[]'* ]] && echo "PASS  Loki has demo-app logs" || { echo "FAIL  no logs in Loki: ${logs:0:200}"; fail=1; }

  traces="$(incluster 'http://tempo.monitoring:3200/api/search?tags=service.name%3Ddemo-app&limit=5')"
  [[ "$traces" == *'"traceID"'* ]] && echo "PASS  Tempo has demo-app traces" || { echo "FAIL  no traces in Tempo: ${traces:0:200}"; fail=1; }

  rules="$(incluster 'http://kps-prometheus.monitoring:9090/api/v1/rules?type=alert')"
  [[ "$rules" == *DemoAppHighErrorRate* ]] && echo "PASS  demo-app alert rules loaded" || { echo "FAIL  alert rules missing"; fail=1; }
  return $fail
}

case "${1:-}" in
  install) install ;;
  verify) verify ;;
  *) sed -n '2,4p' "$0"; exit 2 ;;
esac
