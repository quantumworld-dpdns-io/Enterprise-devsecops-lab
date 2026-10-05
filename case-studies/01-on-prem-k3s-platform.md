# Case study 1: On-premises Kubernetes platform

*An NDA-safe write-up. Names, addresses, topology details and product identifiers are
omitted or generalised. The public reconstruction is this repository.*

## Problem

A product team needed one integration environment for a multi-service application (a web
front end, event-processing services, message brokers, analytics databases and an ML
service). Constraints:

- On-premises only: a single hypervisor host, no cloud, limited RAM.
- The lab network had no general internet egress, and outbound TLS went through an
  inspecting firewall.
- Rebuilds had to be repeatable. Hand-built VMs had drifted and nobody could say exactly
  what was running.

## Context

- Workloads: about two dozen containers, some memory-heavy (columnar and time-series
  databases), some bursty (batch workers).
- Stateful data had to survive a cluster rebuild.
- Test VMs (Windows and Linux) had to reach a few cluster services without joining the cluster.

## Architecture

```text
Hypervisor host
 ├─ control-plane VM        k3s server; system add-ons only (tainted)
 ├─ worker VMs (2)          general workloads
 ├─ "burst" worker VM       tainted; only autoscaled batch workers tolerate it
 ├─ data worker VM          tainted, larger; databases only
 ├─ PostgreSQL VM           outside the cluster, so a cluster rebuild never touches data
 ├─ ML host VM              Docker Compose, outside the cluster
 └─ test VMs                reach the cluster through NodePort / SNI passthrough
```

- **Provisioning**: Ansible created the VMs from cloud-init templates, then installed k3s
  (pinned version, air-gap capable). Terraform managed Kubernetes-level objects such as
  NetworkPolicies and PriorityClasses.
- **Delivery**: Kustomize base/overlays per stack, reconciled by Argo CD. Third-party
  components came from upstream Helm charts rendered into the overlays.
- **Ingress**: k3s's Traefik as a DaemonSet on host ports, so any node IP worked and no
  load-balancer controller was needed.
- **Images**: an internal registry as the primary path, with a "tarball into containerd"
  import kept as a break-glass path for when the registry was down.

## Design decisions

| Decision | Why |
|---|---|
| k3s over kubeadm | One binary, embedded datastore, bundled ingress; fits small VMs |
| Taints + labels instead of one VM per service | VMs are capacity, not service boundaries; heavy and bursty workloads are fenced, everything else bin-packs |
| PostgreSQL outside the cluster | Cluster rebuilds are routine; data loss is not |
| Priority classes | Under memory pressure, batch workers are evicted before the console or brokers |
| Two image paths | Registry for speed, air-gap import for resilience |

## Implementation highlights

- Ansible roles for VM templates (Linux and Windows), k3s server/agent, air-gap images,
  containerd registry config, an internal PKI, PostgreSQL, and log forwarding.
- NetworkPolicies managed as code with Terraform's Kubernetes provider (one set per namespace).
- A capacity rebalance: right-sized VM memory, PodDisruptionBudgets, topology spread
  constraints and the descheduler, so pods re-spread after node maintenance.

## Security controls

- Default-deny NetworkPolicies per namespace, explicit allow-lists.
- An internal CA for service certificates; mTLS on broker connections with a pinned CA that
  fails closed.
- No guest has general internet access; image supply is controlled.
- Accepted risks written down with a review trigger (for example a plain-HTTP internal
  registry, a self-signed hypervisor certificate).

## Failure scenarios and troubleshooting

| Symptom | Root cause | Fix |
|---|---|---|
| Hypervisor "memory full" alarms while workloads looked fine | The memory percentage the dashboard showed included page cache, and ballooning distorted guest-reported usage | Alert on the right metric; disable ballooning on Kubernetes nodes |
| CI jobs failed cloning from public Git hosts | The firewall's TLS inspection presented a certificate the runner's containers did not trust | Fetch through a trusted path or add the inspection CA explicitly, a decision for the security owner, never a silent `insecure` flag |
| A VM had no network after cloning | Its NIC was attached to an isolated bridge without uplink | Remap the NIC to the correct bridge; template the bridge per role |
| Pods piled onto one node after maintenance | The scheduler only places new pods | Descheduler plus topology spread constraints |

## Lessons learned

1. Decide what is capacity and what is a boundary. Taints made that explicit.
2. Keep state outside anything you rebuild often.
3. Every "temporary" exception needs an owner and a review date, or it becomes permanent.
4. The break-glass path must be exercised, or it will not work when you need it.

## Public evidence

| Professional pattern | Reconstruction in this repo |
|---|---|
| Ansible-built k3s on VMs | [ansible/roles/k3s](../ansible/roles/k3s), [terraform/environments/proxmox](../terraform/environments/proxmox) |
| Kustomize overlays + Argo CD | [kubernetes/platform](../kubernetes/platform), [kubernetes/argocd](../kubernetes/argocd) |
| Air-gap image import | `scripts/cluster.sh import`, the `k3s_airgap` option of the k3s role |
| Default-deny networking, verified | [scripts/e2e.sh](../scripts/e2e.sh) |
| Control-plane taint, priority, PDB, spread | Terraform k3s module, [demo-app chart](../kubernetes/helm/demo-app) |

The public lab also adds what the professional setup did not have: authored Helm charts, an
umbrella observability chart, and Cilium with Hubble.

## 中文摘要

在單一地端 hypervisor、無一般對外網路、對外 TLS 會被防火牆檢查的條件下，為產品團隊建立可重複重建的 k3s 整合測試平台：Ansible 建 VM 與安裝 k3s、Terraform 管理 NetworkPolicy 與 PriorityClass、Kustomize overlay + Argo CD 交付；以 taint/label 區隔資料型與突發型工作負載，PostgreSQL 放在叢集外避免重建時遺失資料；registry 為主要映像來源、tarball 匯入 containerd 為 break-glass。本 repo 以開源方式重建同樣的模式，並補上自寫 Helm chart、umbrella 可觀測性 chart 與 Cilium/Hubble。
