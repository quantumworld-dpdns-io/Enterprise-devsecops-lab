# Cloud variants: EKS and AKS

The platform's cloud variants are written to production standards but not applied from this
repository. Every change is formatted, validated, linted (tflint) and scanned (Checkov,
Trivy). A `plan` runs automatically once the repository is connected to an account through
OIDC.

| Concern | AWS (`terraform/modules/aws-eks`) | Azure (`terraform/modules/azure-aks`) |
|---|---|---|
| Network | 3-AZ VPC, private node subnets, NAT (single in dev), S3 gateway endpoint, reject flow logs, default SG emptied | VNet, node subnet with NSG, Azure CNI overlay |
| CNI / NetworkPolicy | VPC CNI with native NetworkPolicy | Cilium dataplane and Cilium network policy |
| Control-plane access | EKS access entries (API mode), no `aws-auth`, no creator-admin bootstrap; private endpoint, public only from listed CIDRs | Entra ID-only (local accounts disabled), Azure RBAC, authorized IP ranges, private cluster option |
| Secrets encryption | Customer-managed KMS key with yearly rotation, scoped key policy | Key Vault (premium, HSM-backed) KMS key with rotation policy, purge protection |
| Workload identity | EKS Pod Identity association, role scoped to one S3 prefix | Workload Identity federated credential, Key Vault Secrets User only |
| Node hardening | AL2023, IMDSv2 required with hop limit 1, SSM instead of SSH, encrypted gp3 | AzureLinux, ephemeral OS disks, host encryption, system pool for critical add-ons only |
| Logging | Control-plane logs (API, audit, authenticator, ...) to KMS-encrypted CloudWatch, 365 days | Container Insights to Log Analytics with a daily ingestion cap |
| Upgrades | Standard support policy (no silent extended-support cost) | Automatic patch channel, node image channel |
| Cost (FinOps) | Spot node group in dev, single NAT, S3 endpoint, mandatory cost tags | Spot apps pool in dev, Free tier in dev, Log Analytics daily cap, cost tags |

## CI access without stored keys

`terraform/modules/github-oidc-aws` and `github-oidc-azure` create the trust:

| Identity | Can be used by | Permissions |
|---|---|---|
| plan | pull requests and branches of this repository | read-only (AWS `ReadOnlyAccess`, Azure `Reader`) plus state access |
| apply | jobs in the protected `production` environment only | write, fenced by the trust condition, required reviewers and (in real accounts) a permissions boundary |

To enable `plan`, set repository variables (not secrets, since nothing secret is stored):

| Cloud | Variables |
|---|---|
| AWS | `AWS_PLAN_ROLE_ARN`, `AWS_REGION`, `TF_STATE_BUCKET` |
| Azure | `AZURE_PLAN_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TF_STATE_RG`, `TF_STATE_SA` |

## Checkov exceptions

Each skip is written next to the resource with its reason (`#checkov:skip=...`). The current
set:

| Check | Resource | Reason |
|---|---|---|
| CKV_AWS_39 | EKS cluster | Public endpoint is off unless CIDRs are given, then CIDR-restricted |
| CKV_AWS_339 | EKS cluster | Pinned version input; the scanner's list lags EKS releases |
| CKV_AWS_18 / CKV2_AWS_62 / CKV_AWS_144 | App S3 bucket | Access audited via CloudTrail data events; no event consumer; replication is a per-data-class DR decision |
| CKV_AZURE_189 / CKV2_AZURE_32 | Key Vault | Public-mode KMS needs a reachable vault (ACL default-deny); private endpoint is the production variant |
| CKV_AZURE_40 | KMS key | Expiry handled by the rotation policy |
| CKV_AZURE_115 / 170 / 117 / 6 | AKS | Private API, paid SKU and disk encryption set are production toggles; authorized IPs come from a required input |

## Why both clouds

The production experience behind this lab is on-premises (k3s on hypervisors). These
modules show the same platform decisions in the two clouds most European employers
run, with each provider's native identity, key management and network controls instead
of a lowest-common-denominator abstraction.
