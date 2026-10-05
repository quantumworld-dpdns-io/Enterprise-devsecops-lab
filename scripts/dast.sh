#!/usr/bin/env bash
# DAST against the app exactly as a client sees it (TLS, headers, cookies, error pages):
#   1. OWASP ZAP baseline: passive scan, safe for shared environments.
#   2. Nuclei: template checks for misconfigurations and exposures, intrusive/DoS excluded.
# Both scanners join the lab network and resolve the app host to the ingress node.
#
# Exit 0 = no ZAP FAIL-level alerts and no Nuclei finding of medium severity or above.
# ZAP rule levels live in security/dast/zap-rules.tsv; every IGNORE there needs a reason.
# NUCLEI=0 skips Nuclei. The stage never passes silently: a scanner that cannot run fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
HOST="${APP_HOST:-demo.lab.example}"
INGRESS_NODE="${INGRESS_NODE:-$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLUSTER}-server-1")}"
ZAP_IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"
NUCLEI_IMAGE="${NUCLEI_IMAGE:-projectdiscovery/nuclei:v3.11.1}"
NUCLEI_TEMPLATES_VERSION="${NUCLEI_TEMPLATES_VERSION:-v10.4.9}"
CURL="${CURL:-curl}"
read -r -a CURL_OPTS <<<"${CURL_OPTS:-}"

mkdir -p "$ROOT/reports"
cp "$ROOT/security/dast/zap-rules.tsv" "$ROOT/reports/zap-rules.tsv"
chmod 777 "$ROOT/reports" 2>/dev/null || true

host_root="$ROOT"
if command -v cygpath >/dev/null 2>&1; then host_root="$(cygpath -w "$ROOT")"; fi

# ---- 1. ZAP baseline (-I: warnings reported, FAIL-level rules fail the stage) ----
MSYS_NO_PATHCONV=1 docker run --rm \
  --network "${CLUSTER}-net" \
  --add-host "${HOST}:${INGRESS_NODE}" \
  -v "${host_root}/reports:/zap/wrk:rw" \
  "$ZAP_IMAGE" zap-baseline.py \
    -t "https://${HOST}/api/v1/info" \
    -c zap-rules.tsv \
    -r zap-report.html -J zap-report.json -w zap-report.md \
    -I -s
echo "ZAP report: reports/zap-report.html"

[[ "${NUCLEI:-1}" == "1" ]] || exit 0

# ---- 2. Nuclei with a pinned template release ----
# Templates are fetched by the host's curl into a cache, so a TLS-intercepting egress proxy
# that the container does not trust cannot break (or silently skip) the scan.
tpl="$ROOT/.kube/nuclei-templates-${NUCLEI_TEMPLATES_VERSION}"
if [[ ! -d "$tpl" ]]; then
  mkdir -p "$tpl"
  "$CURL" "${CURL_OPTS[@]}" -fsSL \
    "https://github.com/projectdiscovery/nuclei-templates/archive/refs/tags/${NUCLEI_TEMPLATES_VERSION}.tar.gz" \
    | tar -xz -C "$tpl" --strip-components=1
fi
host_tpl="$tpl"
if command -v cygpath >/dev/null 2>&1; then host_tpl="$(cygpath -w "$tpl")"; fi

rm -f "$ROOT/reports/nuclei.jsonl"
MSYS_NO_PATHCONV=1 docker run --rm \
  --network "${CLUSTER}-net" \
  --add-host "${HOST}:${INGRESS_NODE}" \
  -v "${host_root}/reports:/out:rw" \
  -v "${host_tpl}:/templates:ro" \
  "$NUCLEI_IMAGE" \
    -u "https://${HOST}" \
    -t /templates/http -t /templates/ssl \
    -tags misconfig,exposure,tech,ssl \
    -etags intrusive,dos,fuzz \
    -jsonl -o /out/nuclei.jsonl -silent -disable-update-check -no-interactsh
touch "$ROOT/reports/nuclei.jsonl"

if grep -qE '"severity":"(medium|high|critical)"' "$ROOT/reports/nuclei.jsonl"; then
  echo "Nuclei: medium+ findings (reports/nuclei.jsonl):"
  grep -E '"severity":"(medium|high|critical)"' "$ROOT/reports/nuclei.jsonl" | cut -c1-300
  exit 1
fi
echo "Nuclei: no medium+ findings; $(wc -l < "$ROOT/reports/nuclei.jsonl") info/low results in reports/nuclei.jsonl"
