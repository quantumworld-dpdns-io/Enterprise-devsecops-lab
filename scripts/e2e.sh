#!/usr/bin/env bash
# End-to-end checks against a running local cluster. Exit non-zero on any failure.
#  1. every node Ready
#  2. demo-app reachable through Traefik over TLS, cert issued by the lab CA
#  3. security headers present on the public response; internal endpoints not routed
#  4. NetworkPolicy: a pod outside the allowed namespaces is blocked
#  5. Pod Security Admission: a privileged pod is rejected in the demo namespace
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
INGRESS_ADDR="${INGRESS_ADDR:-127.0.0.1}"   # the server node IP when inside a CI job container
HTTPS_PORT="${HTTPS_PORT:-8443}"            # 443 when inside a CI job container
HOST="${APP_HOST:-demo.lab.example}"
kc="$ROOT/.kube/${CLUSTER}.yaml"
if command -v cygpath >/dev/null 2>&1; then kc="$(cygpath -w "$kc")"; fi
k() { kubectl --kubeconfig "$kc" "$@"; }

pass=0; fail=0
ok()  { echo "PASS  $*"; pass=$((pass + 1)); }
bad() { echo "FAIL  $*"; fail=$((fail + 1)); }

# 1. nodes
not_ready="$(k get nodes --no-headers | awk '$2!="Ready"' | wc -l)"
[[ "$not_ready" -eq 0 ]] && ok "all nodes Ready" || bad "$not_ready node(s) not Ready"

# 2 + 3. ingress, TLS and headers
k -n demo rollout status deploy/demo-app --timeout=120s >/dev/null
url="https://${HOST}:${HTTPS_PORT}"
resolve=(--resolve "${HOST}:${HTTPS_PORT}:${INGRESS_ADDR}")
body="$(curl -sk "${resolve[@]}" "$url/api/v1/info" || true)"
[[ "$body" == *'"service":"demo-app"'* ]] && ok "ingress serves demo-app" || bad "ingress response: $body"

issuer="$(echo | openssl s_client -connect "${INGRESS_ADDR}:${HTTPS_PORT}" -servername "$HOST" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true)"
[[ "$issuer" == *"Lab Example Root CA"* ]] && ok "TLS cert issued by lab CA" || bad "unexpected issuer: $issuer"

headers="$(curl -skI "${resolve[@]}" "$url/api/v1/info" | tr -d '\r')"
for h in Content-Security-Policy X-Content-Type-Options X-Frame-Options Strict-Transport-Security; do
  grep -qi "^$h:" <<<"$headers" && ok "header $h" || bad "missing header $h"
done
# Unknown paths reach the app too, so even a 404 must carry the headers.
grep -qi '^Strict-Transport-Security:' <<<"$(curl -skI "${resolve[@]}" "$url/no-such-page" | tr -d '\r')" \
  && ok "404 responses carry security headers" || bad "404 response lacks security headers"

# Internal endpoints live on the admin port and must not be reachable through the ingress
# (regression test for the Nuclei "prometheus-metrics" finding).
for p in /metrics /healthz /readyz; do
  code="$(curl -sk -o /dev/null -w '%{http_code}' "${resolve[@]}" "$url$p")"
  [[ "$code" == "404" ]] && ok "$p not exposed through ingress" || bad "$p reachable through ingress (HTTP $code)"
done

# 4. NetworkPolicy. Positive control first: monitoring IS allow-listed, so the same
#    probe must succeed there. Otherwise a "blocked" result could just be a broken probe.
k delete pod np-allowed -n monitoring --ignore-not-found --wait=true >/dev/null
k run np-allowed -n monitoring --image=busybox:1.36 --restart=Never --command -- \
  wget -q -T 5 -O- http://demo-app.demo.svc.cluster.local:9090/healthz >/dev/null
k wait -n monitoring --for=jsonpath='{.status.phase}'=Succeeded pod/np-allowed --timeout=60s >/dev/null 2>&1 \
  && ok "NetworkPolicy allows traffic from the monitoring namespace" \
  || bad "positive control failed (phase: $(k get pod np-allowed -n monitoring -o jsonpath='{.status.phase}'))"
k delete pod np-allowed -n monitoring --ignore-not-found --wait=false >/dev/null

# Negative: default namespace is not in the allow-list
k delete pod np-probe -n default --ignore-not-found --wait=true >/dev/null
k run np-probe -n default --image=busybox:1.36 --restart=Never --command -- \
  wget -q -T 5 -O- http://demo-app.demo.svc.cluster.local:9090/healthz >/dev/null
k wait -n default --for=jsonpath='{.status.phase}'=Failed pod/np-probe --timeout=60s >/dev/null 2>&1 \
  && ok "NetworkPolicy blocks traffic from an unlisted namespace" \
  || bad "np-probe was not blocked (phase: $(k get pod np-probe -n default -o jsonpath='{.status.phase}'))"
k delete pod np-probe -n default --ignore-not-found --wait=false >/dev/null

# 5. Pod Security Admission: privileged pod must be rejected in a restricted namespace
if k run psa-probe -n demo --image=busybox:1.36 --restart=Never --privileged=true -- true >/dev/null 2>&1; then
  bad "privileged pod was admitted in namespace demo"
  k delete pod psa-probe -n demo --ignore-not-found >/dev/null
else
  ok "Pod Security Admission rejects privileged pod"
fi

echo "---- $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
