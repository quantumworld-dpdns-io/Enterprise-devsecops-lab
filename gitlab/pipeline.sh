#!/usr/bin/env bash
# Run this repository's .gitlab-ci.yml on the local GitLab (gitlab/bootstrap.sh up|runner first).
# Pushes a snapshot of the working tree to `main`, then the same tree to branch `ci-check`
# and opens a merge request, which triggers the merge-request pipeline (secrets, lint, test,
# SAST, SCA, IaC scan, policy, SBOM). Jobs limited to the default branch (build, sign,
# deploy) are skipped by their rules on an MR pipeline.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
URL="http://127.0.0.1:8929"
T="$(cat "$DIR/.secrets/root_token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $T" "$@"; }
PY="$(command -v python3 || command -v python)"
json() { "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

pid="$(api "$URL/api/v4/projects?search=enterprise-devsecops-lab" | json 'd[0]["id"]')"

tmp="$(mktemp -d)"
(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 -I{} cp --parents {} "$tmp/")
remote="http://root:${T}@127.0.0.1:8929/root/enterprise-devsecops-lab.git"
# Git on Windows does not record the executable bit; set it explicitly for scripts.
(cd "$tmp" && git init -q -b main && git add -A \
  && { git ls-files -z '*.sh' | xargs -0 -r git update-index --chmod=+x; } \
  && git -c user.name="lab snapshot" -c user.email=snapshot@lab.example commit -qm "snapshot $(date -u +%FT%TZ)")
# main is a protected branch (no force push), so it is seeded once and never rewritten.
# The snapshot always goes to ci-check. ci.skip: no pipeline for the push itself.
if ! git ls-remote --exit-code "$remote" refs/heads/main >/dev/null 2>&1; then
  git -C "$tmp" push -q -o ci.skip "$remote" main:main
fi
git -C "$tmp" push -q -f -o ci.skip "$remote" main:ci-check
rm -rf "$tmp"

# Pushes above carry ci.skip, so nothing has run yet. An MR needs a diff and a new commit on
# its source branch to start a pipeline: add one marker commit through the API.
marker="{\"branch\":\"ci-check\",\"commit_message\":\"ci: trigger MR pipeline\",\"actions\":[{\"action\":\"create\",\"file_path\":\".ci-check\",\"content\":\"$(date -u +%FT%TZ)\"}]}"
api -X POST "$URL/api/v4/projects/$pid/repository/commits" -H 'Content-Type: application/json' --data "$marker" >/dev/null
api -X POST "$URL/api/v4/projects/$pid/merge_requests" \
  --data "source_branch=ci-check&target_branch=main&title=CI check" >/dev/null 2>&1 || true

echo "waiting for the merge-request pipeline..."
for _ in $(seq 1 180); do
  p="$(api "$URL/api/v4/projects/$pid/pipelines?source=merge_request_event&per_page=1")"
  status="$(echo "$p" | json 'd[0]["status"] if d else "none"')"
  case "$status" in success|failed|canceled) break ;; esac
  sleep 20
done
plid="$(echo "$p" | json 'd[0]["id"]')"
echo "pipeline $plid: $status"
api "$URL/api/v4/projects/$pid/pipelines/$plid/jobs?per_page=100" \
  | json '"\n".join("%-16s %-10s %s" % (j["name"], j["stage"], j["status"]) for j in sorted(d, key=lambda j: j["id"]))'
[[ "$status" == "success" ]]
