#!/usr/bin/env bash
# Resolve and install pinned third-party charts from kubernetes/charts.txt.
#
#   charts.sh ref <name>        print what to pass to `helm install` for <name>:
#                               a cached .tgz if one exists, else "<name> --repo <url> --version <v>"
#   charts.sh fetch [name ...]  pre-download charts into .kube/charts/ with $CURL
#
# Why `fetch` exists: on networks with a TLS-intercepting proxy, a container's CA
# bundle does not trust the proxy, so `helm pull` fails with "x509: certificate signed
# by unknown authority". The host's curl already trusts the system store, so it can
# download the .tgz instead, and nobody has to change CA trust to run the lab.
# (Windows: CURL=curl.exe uses the Windows certificate store.)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$ROOT/kubernetes/charts.txt"
CACHE="$ROOT/.kube/charts"
CURL="${CURL:-curl}"
# Extra curl flags. Example: CURL_OPTS=--ssl-revoke-best-effort with Windows schannel when
# the proxy certificate's revocation endpoint is unreachable (the chain is still validated).
read -r -a CURL_OPTS <<<"${CURL_OPTS:-}"
PYTHON="$(command -v python3 || command -v python)"

lookup() { awk -v n="$1" '$1==n {print $2, $3}' "$LIST"; }

# Find the download URL of <name> <version> in a repository index.yaml.
chart_url() {
  "$PYTHON" -c '
import re, sys
idx, name, ver = sys.argv[1:]
txt = open(idx, encoding="utf-8").read()
block = re.search(r"\n  " + re.escape(name) + r":\n(.*?)(?=\n  [A-Za-z0-9_.-]+:\n|\Z)", txt, re.S).group(1)
for entry in re.split(r"\n  - ", block):
    if re.search(r"\n\s*version: " + re.escape(ver) + r"\s*(\n|$)", "\n" + entry):
        print(re.search(r"urls:\n\s*- ([^\n]+)", entry).group(1).strip())
        break
' "$@"
}

case "${1:-}" in
  ref)
    read -r repo version < <(lookup "${2:?chart name}") || { echo "unknown chart $2" >&2; exit 1; }
    if [[ -f "$CACHE/$2-${version}.tgz" ]]; then
      echo "/w/.kube/charts/$2-${version}.tgz"   # path as seen inside the helm container
    else
      echo "$2 --repo $repo --version $version"
    fi
    ;;
  fetch)
    shift
    mkdir -p "$CACHE"
    names=("$@")
    if [[ ${#names[@]} -eq 0 ]]; then mapfile -t names < <(grep -vE '^\s*(#|$)' "$LIST" | awk '{print $1}'); fi
    for n in "${names[@]}"; do
      read -r repo version < <(lookup "$n")
      tgz="$CACHE/$n-${version}.tgz"
      if [[ -f "$tgz" ]]; then echo "cached  $n $version"; continue; fi
      idx="$CACHE/index-$(printf '%s' "$repo" | md5sum | cut -c1-8).yaml"
      [[ -f "$idx" ]] || "$CURL" "${CURL_OPTS[@]}" -fsSL -o "$idx" "$repo/index.yaml"
      url="$(chart_url "$idx" "$n" "$version")"
      [[ -n "$url" ]] || { echo "version $version of $n not found in index" >&2; exit 1; }
      [[ "$url" == http* ]] || url="$repo/$url"
      "$CURL" "${CURL_OPTS[@]}" -fsSL -o "$tgz" "$url"
      echo "fetched $n $version"
    done
    ;;
  vendor)
    # Populate <chart>/charts/ with the pinned dependency .tgz files, fetching any that are
    # missing, so `helm install` needs no repository access (and no `helm dependency build`).
    chart_dir="${2:?chart directory}"
    mkdir -p "$chart_dir/charts"
    deps="$(awk '/^dependencies:/{d=1;next} d&&/- name:/{print $3}' "$chart_dir/Chart.yaml")"
    for n in $deps; do
      read -r _ version < <(lookup "$n")
      [[ -f "$CACHE/$n-${version}.tgz" ]] || "$0" fetch "$n"
      cp "$CACHE/$n-${version}.tgz" "$chart_dir/charts/"
      echo "vendored $n $version"
    done
    ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
