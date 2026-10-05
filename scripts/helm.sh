#!/usr/bin/env bash
# Run Helm in a container attached to the lab network, so no local Helm install
# is needed and the API is reached directly on the node network (server IP, port 6443).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-lab}"
HELM_IMAGE="${HELM_IMAGE:-alpine/helm:3.16.4}"

src="$ROOT/.kube/${CLUSTER}.yaml"
internal="$ROOT/.kube/${CLUSTER}-internal.yaml"
server_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLUSTER}-server-1")"
sed "s#https://[0-9.]*:[0-9]*#https://${server_ip}:6443#" "$src" > "$internal"
chmod 600 "$internal"

host_root="$ROOT"
if command -v cygpath >/dev/null 2>&1; then host_root="$(cygpath -w "$ROOT")"; fi

MSYS_NO_PATHCONV=1 exec docker run --rm \
  --network "${CLUSTER}-net" \
  -v "${host_root}:/w" -w /w \
  -e KUBECONFIG="/w/.kube/${CLUSTER}-internal.yaml" \
  -e HELM_CACHE_HOME=/w/.kube/helm-cache \
  -e HELM_CONFIG_HOME=/w/.kube/helm-config \
  "$HELM_IMAGE" "$@"
