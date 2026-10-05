#!/usr/bin/env bash
# Bring up the local GitLab, create a project, register the runner and validate
# .gitlab-ci.yml with GitLab's own CI linter.
#   gitlab/bootstrap.sh up      start GitLab CE + runner and wait for readiness
#   gitlab/bootstrap.sh lint    create token + project, run the CI lint API on .gitlab-ci.yml
#   gitlab/bootstrap.sh runner  register the runner (tag lab-docker)
#   gitlab/bootstrap.sh down    stop and delete everything, volumes included
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
URL="http://127.0.0.1:8929"
SECRETS="$DIR/.secrets"
CF="$DIR/docker-compose.yml"
if command -v cygpath >/dev/null 2>&1; then CF="$(cygpath -w "$CF")"; fi
# MSYS_NO_PATHCONV: stop Git Bash rewriting container paths (e.g. /var/run/docker.sock) into Windows paths.
compose() { MSYS_NO_PATHCONV=1 docker compose -f "$CF" "$@"; }

rails() { compose exec -T gitlab gitlab-rails runner "$1"; }

token() {
  # A short-lived personal access token for root, created through the Rails console.
  if [[ ! -s "$SECRETS/root_token" ]]; then
    local t; t="glpat-$(openssl rand -hex 16)"
    rails "u=User.find_by_username('root'); pat=u.personal_access_tokens.create!(scopes: ['api'], name: 'lab-bootstrap', expires_at: 7.days.from_now); pat.set_token('$t'); pat.save!" >/dev/null
    echo "$t" > "$SECRETS/root_token"; chmod 600 "$SECRETS/root_token"
  fi
  cat "$SECRETS/root_token"
}

case "${1:-}" in
  up)
    mkdir -p "$SECRETS"
    [[ -s "$SECRETS/root_password" ]] || { openssl rand -base64 24 | tr -d '/+=' > "$SECRETS/root_password"; chmod 600 "$SECRETS/root_password"; }
    compose up -d
    echo "waiting for GitLab (first boot ~5 min)..."
    for _ in $(seq 1 90); do
      # /-/readiness only answers allow-listed IPs; the sign-in page works from the host.
      curl -fsS "$URL/users/sign_in" >/dev/null 2>&1 && { echo "GitLab ready at $URL"; exit 0; }
      sleep 10
    done
    echo "GitLab did not become ready" >&2; exit 1
    ;;
  lint)
    t="$(token)"
    pid="$(curl -fsS -H "PRIVATE-TOKEN: $t" "$URL/api/v4/projects?search=enterprise-devsecops-lab" | python -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')"
    if [[ -z "$pid" ]]; then
      pid="$(curl -fsS -H "PRIVATE-TOKEN: $t" -X POST "$URL/api/v4/projects" \
        --data "name=enterprise-devsecops-lab&visibility=private" | python -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
    fi
    python - "$ROOT/.gitlab-ci.yml" > "$SECRETS/lint-request.json" <<'PY'
import json, sys
print(json.dumps({"content": open(sys.argv[1], encoding="utf-8").read()}))
PY
    curl -fsS -H "PRIVATE-TOKEN: $t" -H 'Content-Type: application/json' \
      -X POST "$URL/api/v4/projects/$pid/ci/lint" --data @"$SECRETS/lint-request.json" \
      | python -c 'import json,sys; d=json.load(sys.stdin); print("valid:", d["valid"]); [print("error:", e) for e in d.get("errors",[])]; [print("warning:", w) for w in d.get("warnings",[])]; sys.exit(0 if d["valid"] else 1)'
    ;;
  runner)
    t="$(token)"
    rt="$(curl -fsS -H "PRIVATE-TOKEN: $t" -X POST "$URL/api/v4/user/runners" \
      --data "runner_type=instance_type&tag_list=lab-docker&description=lab-docker" | python -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
    compose exec -T runner gitlab-runner unregister --all-runners >/dev/null 2>&1 || true
    compose exec -T runner gitlab-runner register --non-interactive \
      --url "http://gitlab.lab.example:8929" --token "$rt" --executor docker \
      --docker-image alpine:3.20 --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
      --docker-volumes /builds:/builds --docker-network-mode lab-gitlab_default >/dev/null
    compose exec -T runner gitlab-runner verify
    ;;
  down)
    compose down -v
    rm -rf "$SECRETS"
    ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
