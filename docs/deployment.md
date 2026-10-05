# Deployment

## Prerequisites

| Tool | Needed for |
|---|---|
| Docker | everything (all other tools run from pinned images) |
| Terraform ≥ 1.6 | cluster lifecycle |
| kubectl | cluster access |
| Go 1.26 | building and testing the app |
| GNU make, bash | the `make` targets (Git Bash on Windows) |

About 8 GB of free RAM covers the cluster, observability and Argo CD.

## Local runtime

```bash
make up              # Terraform cluster, build + import image, platform, demo-app
make e2e             # 14 end-to-end checks
make observability   # umbrella chart: Prometheus, Grafana, Loki, Alloy, Tempo, OTel Collector
make dast            # OWASP ZAP baseline + Nuclei
make argocd          # Argo CD tracking this repository on GitHub
make argocd-verify   # all apps Synced/Healthy, self-heal restores a deleted object
make down            # destroy
```

Grafana and Argo CD are served through the ingress with lab-CA certificates. Add
`127.0.0.1 demo.lab.example grafana.lab.example argocd.lab.example` to your hosts file and use
port 8443. The Grafana admin password is generated at install time and stored only in the
cluster (`kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`).

### Cilium variant, side by side

```bash
make up CLUSTER=cil CNI=cilium NODE_CIDR=10.10.20.0/24 API_PORT=6444 HTTP_PORT=8081 HTTPS_PORT=8444
make cilium-verify CLUSTER=cil HTTPS_PORT=8444
make e2e CLUSTER=cil HTTPS_PORT=8444
```

Each cluster has its own Terraform workspace, node subnet and host ports.

### Behind a TLS-intercepting proxy

If chart downloads fail with `x509: certificate signed by unknown authority`, prefetch with
the host's trusted curl, then run as usual:

```bash
CURL=curl.exe CURL_OPTS=--ssl-revoke-best-effort make charts
```

## Proxmox runtime

1. Build an Ubuntu 24.04 cloud-init template (VM 9000) on the Proxmox host.
2. Export API credentials (never written to files):
   `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`.
3. `cp terraform/environments/proxmox/terraform.tfvars.example terraform.tfvars` and set your SSH key.
4. `terraform -chdir=terraform/environments/proxmox apply`. This writes
   `ansible/inventory/proxmox.yml` from what was actually created.
5. Create and encrypt the vault files from `ansible/examples/`, filling in the k3s token and
   the upstream checksums.
6. `cd ansible && ansible-playbook playbooks/site.yml --ask-vault-pass`.

Workers roll one at a time (`serial: 1`), so a bad change never removes all capacity.

## Cloud variants

See [cloud.md](cloud.md). They are validated, linted and security-scanned on every change,
and planned through OIDC when the repository is connected to an account.

## Remote state

The local runtime keeps state locally (AR-003). Shared environments use remote state with
locking: S3 with `use_lockfile = true` for AWS, an Azure Storage container with Entra ID
auth for Azure. Bucket and account names are passed with `-backend-config`, never committed.

## Verify an image

Images from `main` are signed keylessly and carry SBOM and SLSA provenance attestations.

```bash
IMAGE=ghcr.io/dennislee928/demo-app@sha256:<digest>
cosign verify "$IMAGE" \
  --certificate-identity "https://github.com/dennislee928/enterprise-devsecops-lab/.github/workflows/ci.yml@refs/heads/main" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify-attestation "$IMAGE" --type slsaprovenance1 \
  --certificate-identity "https://github.com/dennislee928/enterprise-devsecops-lab/.github/workflows/ci.yml@refs/heads/main" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

In the cluster, Kyverno performs the same checks at admission
([verify-images.yaml](../kubernetes/supply-chain/verify-images.yaml)).
