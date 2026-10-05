#!/usr/bin/env bash
# Run every linter and security scanner in a pinned container image.
# Same commands locally (make scan), in GitHub Actions and in GitLab CI.
#
#   scan.sh [check ...]     default: all checks
#   checks: secrets lint-yaml lint-tf lint-ansible lint-docker helm kubeconform
#           policy sast-semgrep sast-gosec sca-govuln sca-trivy iac-checkov
#           iac-trivy image sbom policy-kyverno
#
# Reports land in reports/. IMAGE (default demo-app:dev) is scanned by `image`/`sbom`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p reports
IMAGE="${IMAGE:-demo-app:dev}"
HOSTDIR="$ROOT"
if command -v cygpath >/dev/null 2>&1; then HOSTDIR="$(cygpath -w "$ROOT")"; fi
export MSYS_NO_PATHCONV=1

# Pinned tool images. Bump deliberately, never float.
TRIVY=aquasec/trivy:0.58.1
CHECKOV=bridgecrew/checkov:3.2.344
CONFTEST=openpolicyagent/conftest:v0.56.0
SEMGREP=semgrep/semgrep:1.99.0
GITLEAKS=zricethezav/gitleaks:v8.21.2
TFLINT=ghcr.io/terraform-linters/tflint:v0.54.0
YAMLLINT=cytopia/yamllint:1.26
HADOLINT=hadolint/hadolint:v2.12.0
KUBECONFORM=ghcr.io/yannh/kubeconform:v0.6.7
HELM=alpine/helm:3.16.4
PYTHON_IMG=python:3.12-slim
ANSIBLE_LINT_PIP="ansible-core==2.17.7 ansible-lint==24.12.2"
SYFT=anchore/syft:v1.18.1
KYVERNO=ghcr.io/kyverno/kyverno-cli:v1.13.2
KUSTOMIZE=registry.k8s.io/kustomize/kustomize:v5.6.0
GO=golang:1.26-alpine

# Paths directory scanners skip. Keep in sync with .semgrepignore, .checkov.yaml skip-path
# and the .gitleaks.toml allowlist.
#  - local-only, git-ignored state: never published
#  - kubernetes/supply-chain/tests: policy-test fixtures that are non-compliant on purpose
SKIP_DIRS=()
for d in .kube .terraform reports ansible/.collections gitlab/.secrets "**/.terraform" \
         "kubernetes/helm/*/charts" kubernetes/supply-chain/tests; do
  SKIP_DIRS+=(--skip-dirs "$d")
done

run() { docker run --rm -v "${HOSTDIR}:/src" -w /src "$@"; }
run_sock() { docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${HOSTDIR}:/src" -w /src "$@"; }

render() {
  run "$HELM" template demo-app kubernetes/helm/demo-app -n demo \
    --set serviceMonitor.enabled=true --set tracing.otlpEndpoint=otel-collector.monitoring:4317 \
    > reports/rendered-chart.yaml
  run "$KUSTOMIZE" build kubernetes/platform/overlays/local > reports/rendered-platform.yaml
}

check() {
  case "$1" in
    secrets)       run "$GITLEAKS" dir /src --config /src/.gitleaks.toml --no-banner --redact --report-path /src/reports/gitleaks.json ;;
    # Lint exactly what git would publish (tracked + untracked-not-ignored); caches stay out.
    lint-yaml)     mapfile -t yfiles < <(git ls-files -co --exclude-standard '*.yml' '*.yaml' | grep -v '/templates/')
                   run "$YAMLLINT" -c .yamllint.yaml "${yfiles[@]}" ;;
    lint-tf)       for d in terraform/modules/* terraform/environments/*; do
                     run --entrypoint sh "$TFLINT" -c "cd /src/$d && tflint --init >/dev/null && tflint --format compact" || return 1
                   done ;;
    lint-ansible)  run -w /src/ansible -e ANSIBLE_ROLES_PATH=/src/ansible/roles -e ANSIBLE_COLLECTIONS_PATH=/src/ansible/.collections -e PIP_DISABLE_PIP_VERSION_CHECK=1 \
                     "$PYTHON_IMG" sh -c "pip install -q --root-user-action=ignore $ANSIBLE_LINT_PIP && \
                     ansible-galaxy collection install -r requirements.yml -p .collections >/dev/null && \
                     ansible-lint --offline -p" ;;
    lint-docker)   run -i "$HADOLINT" hadolint --failure-threshold warning - < app/Dockerfile ;;
    helm)          run "$HELM" lint kubernetes/helm/demo-app --strict && \
                   "$ROOT/scripts/charts.sh" vendor kubernetes/helm/observability-stack >/dev/null && \
                   run "$HELM" lint kubernetes/helm/observability-stack ;;
    kubeconform)   render && run "$KUBECONFORM" -strict -summary -ignore-missing-schemas \
                     reports/rendered-chart.yaml reports/rendered-platform.yaml ;;
    policy)        render && run "$CONFTEST" verify -p security/policy && \
                   run "$CONFTEST" test -p security/policy reports/rendered-chart.yaml ;;
    policy-kyverno) run "$KYVERNO" test kubernetes/supply-chain/tests ;;
    sast-semgrep)  run "$SEMGREP" semgrep scan --config p/golang --config p/dockerfile \
                     --config p/kubernetes --config p/terraform --error --metrics=off \
                     --sarif --output reports/semgrep.sarif --quiet ;;
    sast-gosec)    run -w /src/app -e GOFLAGS=-buildvcs=false "$GO" sh -c \
                     'go install github.com/securego/gosec/v2/cmd/gosec@v2.29.0 >/dev/null 2>&1 && gosec -quiet ./...' ;;
    sca-govuln)    run -w /src/app "$GO" sh -c \
                     'go install golang.org/x/vuln/cmd/govulncheck@v1.1.4 >/dev/null 2>&1 && govulncheck ./...' ;;
    sca-trivy)     run "$TRIVY" fs --scanners vuln,secret --severity HIGH,CRITICAL --exit-code 1 \
                     --ignore-unfixed "${SKIP_DIRS[@]}" /src ;;
    iac-checkov)   render && run "$CHECKOV" --config-file /src/.checkov.yaml -d /src --output cli --output sarif \
                     --output-file-path console,/src/reports ;;
    iac-trivy)     run "$TRIVY" config --severity HIGH,CRITICAL --exit-code 1 "${SKIP_DIRS[@]}" /src ;;
    image)         run_sock "$TRIVY" image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed "$IMAGE" ;;
    sbom)          run_sock "$SYFT" "$IMAGE" -o cyclonedx-json=/src/reports/sbom.cdx.json -o table=/src/reports/sbom.txt \
                     && echo "SBOM: reports/sbom.cdx.json" ;;
    *) echo "unknown check: $1" >&2; return 2 ;;
  esac
}

ALL=(secrets lint-yaml lint-tf lint-ansible lint-docker helm kubeconform policy policy-kyverno sast-semgrep sast-gosec sca-govuln sca-trivy iac-checkov iac-trivy image sbom)
CHECKS=("$@"); [[ ${#CHECKS[@]} -eq 0 ]] && CHECKS=("${ALL[@]}")

failed=()
for c in "${CHECKS[@]}"; do
  echo "::group::$c"
  if check "$c"; then echo "OK    $c"; else echo "FAIL  $c"; failed+=("$c"); fi
  echo "::endgroup::"
done

echo "==== ${#CHECKS[@]} checks, ${#failed[@]} failed ${failed[*]:-}"
[[ ${#failed[@]} -eq 0 ]]
