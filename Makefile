# Run from Git Bash on Windows, or any POSIX shell on Linux/macOS.
# Every tool except docker, terraform, kubectl and go runs from a pinned container image.
SHELL       := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

CLUSTER ?= lab
IMAGE   ?= demo-app:dev
TF_DIR  := terraform/environments/local
KUBECONFIG_FILE := .kube/$(CLUSTER).yaml
# Several clusters can run side by side; each needs its own node subnet and host ports.
#   make up CLUSTER=cil CNI=cilium NODE_CIDR=10.10.20.0/24 API_PORT=6444 HTTP_PORT=8081 HTTPS_PORT=8444
CNI        ?= flannel
NODE_CIDR  ?= 10.10.10.0/24
API_PORT   ?= 6443
HTTP_PORT  ?= 8080
HTTPS_PORT ?= 8443
# One Terraform workspace per cluster ("lab" keeps the default workspace).
TF_WORKSPACE := $(if $(filter lab,$(CLUSTER)),default,$(CLUSTER))
export CLUSTER API_PORT HTTPS_PORT TF_WORKSPACE
export TF_VAR_cluster_name := $(CLUSTER)
export TF_VAR_cni          := $(CNI)
export TF_VAR_network_cidr := $(NODE_CIDR)
export TF_VAR_api_port     := $(API_PORT)
export TF_VAR_http_port    := $(HTTP_PORT)
export TF_VAR_https_port   := $(HTTPS_PORT)

.PHONY: help up down build cluster cilium-verify molecule argocd-verify platform deploy e2e test scan lint security dast observability charts argocd nda ci

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

up: cluster build platform deploy ## Create the cluster and deploy everything

cluster: ## Terraform: 3-node k3s-in-Docker cluster (CNI=cilium for Cilium + Hubble)
	TF_WORKSPACE= terraform -chdir=$(TF_DIR) init -input=false >/dev/null
	TF_WORKSPACE= terraform -chdir=$(TF_DIR) workspace select -or-create $(TF_WORKSPACE) >/dev/null
	terraform -chdir=$(TF_DIR) apply -auto-approve -input=false
	./scripts/cluster.sh kubeconfig
	@if [ "$(CNI)" = "cilium" ]; then ./scripts/cilium.sh install; else ./scripts/cluster.sh wait; fi

cilium-verify: ## Cilium agent health + Hubble sees a NetworkPolicy drop
	./scripts/cilium.sh verify

molecule: ## Molecule test of the linux-hardening role (Docker)
	./scripts/molecule.sh linux-hardening

# Every build gets an immutable, content-derived tag, so a changed image always rolls out
# and the same tag can never point at two different images.
build: ## Build the app image and import it into every node
	go -C app test -count=1 ./...
	docker build -t $(IMAGE) --build-arg VERSION=$$(git describe --tags --always 2>/dev/null || echo dev) app
	@mkdir -p .kube
	@tag="sha-$$(docker image inspect -f '{{.Id}}' $(IMAGE) | cut -d: -f2 | cut -c1-12)"; \
	  docker tag $(IMAGE) demo-app:$$tag && echo $$tag > .kube/$(CLUSTER)-image-tag && echo "image tag: $$tag"
	./scripts/cluster.sh import demo-app:$$(cat .kube/$(CLUSTER)-image-tag)

platform: ## cert-manager + namespaces, Pod Security, default-deny, lab CA
	./scripts/helm.sh upgrade --install cert-manager $$(./scripts/charts.sh ref cert-manager) \
	  -n cert-manager --create-namespace --set crds.enabled=true --wait --timeout 5m
	kubectl --kubeconfig $(KUBECONFIG_FILE) apply -k kubernetes/platform/overlays/local
	kubectl --kubeconfig $(KUBECONFIG_FILE) wait --for=condition=Ready clusterissuer/lab-ca --timeout=120s

deploy: ## Helm: demo-app into the restricted namespace
	./scripts/helm.sh upgrade --install demo-app kubernetes/helm/demo-app -n demo \
	  -f kubernetes/helm/demo-app/ci/local-values.yaml --set image.tag=$$(cat .kube/$(CLUSTER)-image-tag) \
	  $(DEPLOY_ARGS) --wait --timeout 3m

observability: ## Prometheus, Grafana, Loki, Tempo, OTel Collector (about 3 GB RAM)
	./scripts/observability.sh install
	$(MAKE) deploy DEPLOY_ARGS="--set serviceMonitor.enabled=true --set tracing.otlpEndpoint=http://otel-collector.monitoring:4317"
	./scripts/observability.sh verify

charts: ## Pre-download pinned charts (TLS-intercepting proxy: CURL=curl.exe on Windows)
	./scripts/charts.sh fetch

argocd: ## Argo CD + app-of-apps pointing at this repository
	./scripts/helm.sh upgrade --install argocd $$(./scripts/charts.sh ref argo-cd) \
	  -n argocd --create-namespace -f kubernetes/argocd/values.yaml --wait --timeout 5m
	kubectl --kubeconfig $(KUBECONFIG_FILE) apply -k kubernetes/argocd

argocd-verify: ## After `make argocd`: all apps Synced/Healthy, and self-heal restores a deleted object
	./scripts/argocd-verify.sh

e2e: ## End-to-end checks: ingress, TLS, headers, exposure, NetworkPolicy, Pod Security
	./scripts/e2e.sh

dast: ## OWASP ZAP baseline + Nuclei against the running app
	./scripts/dast.sh

test: ## Unit tests and policy tests
	go -C app vet ./...
	go -C app test -race -count=1 ./... 2>/dev/null || go -C app test -count=1 ./...
	./scripts/scan.sh policy policy-kyverno

lint: ## Linters only
	./scripts/scan.sh lint-yaml lint-tf lint-ansible lint-docker helm kubeconform

security: ## Secret, SAST, SCA, IaC, image scans and SBOM
	./scripts/scan.sh secrets policy sast-semgrep sast-gosec sca-govuln sca-trivy iac-checkov iac-trivy image sbom

scan: lint security ## lint + security

nda: ## Private NDA denylist over tree and history
	./scripts/nda-scan.sh
	./scripts/nda-scan.sh --history

ci: test scan nda ## What CI runs before deploy

down: ## Destroy the cluster
	terraform -chdir=$(TF_DIR) destroy -auto-approve -input=false
	rm -f .kube/$(CLUSTER)*.yaml
