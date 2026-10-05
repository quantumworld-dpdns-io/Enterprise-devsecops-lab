#!/usr/bin/env bash
# Verify the GitOps loop after `make argocd` (Argo CD tracking this GitHub repository):
#   1. every Application is Synced/Healthy
#   2. self-heal: a managed object deleted by hand is restored by Argo CD
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
kc="$ROOT/.kube/${CLUSTER}.yaml"
if command -v cygpath >/dev/null 2>&1; then kc="$(cygpath -w "$kc")"; fi
k() { kubectl --kubeconfig "$kc" "$@"; }

fail=0
for _ in $(seq 1 60); do
  pending="$(k -n argocd get applications -o jsonpath='{range .items[*]}{.status.sync.status}/{.status.health.status}{"\n"}{end}' | grep -vc '^Synced/Healthy$' || true)"
  [[ "$pending" -eq 0 ]] && break
  sleep 10
done

while read -r name sync health; do
  [[ "$sync/$health" == "Synced/Healthy" ]] && echo "PASS  $name Synced/Healthy" || { echo "FAIL  $name $sync/$health"; fail=1; }
done < <(k -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}')

k -n demo delete networkpolicy demo-app --wait=true >/dev/null
for _ in $(seq 1 30); do k -n demo get networkpolicy demo-app >/dev/null 2>&1 && break; sleep 5; done
if k -n demo get networkpolicy demo-app >/dev/null 2>&1; then
  echo "PASS  self-heal restored the deleted NetworkPolicy"
else
  echo "FAIL  NetworkPolicy not restored"; fail=1
fi
exit $fail
