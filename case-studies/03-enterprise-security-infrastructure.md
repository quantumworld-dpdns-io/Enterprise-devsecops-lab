# Case study 3: Enterprise security infrastructure

*An NDA-safe write-up. No employer, vendor, tenant, policy, host or address details, and no
product design specifics. Tools are described by category.*

## Problem

An on-premises lab had to behave like a small enterprise estate for security testing:
Windows and Linux endpoints under an enterprise EDR, vulnerability management for hosts and
containers, central monitoring with alerting, and a pipeline that collects endpoint
telemetry. All of it inside segmented networks, with an isolated segment for attack
simulation.

## Context

- A commercial enterprise EDR with its management server.
- A commercial vulnerability-management platform, including a container sensor in Kubernetes.
- Two hypervisor platforms.
- A Kubernetes cluster for the security services themselves.

## Architecture

```text
Endpoints (Windows, Linux)
   │  EDR agent ─────────────► EDR management server
   │  telemetry ── mTLS ─────► edge gateway ─► message broker ─► processing ─► analytics
   │
Infrastructure
   ├─ Linux / Windows hosts ─► node_exporter ─► Prometheus ─► Alertmanager ─► internal mail relay
   ├─ Hypervisors ─► hypervisor exporters ─► Prometheus
   ├─ Kubernetes ─► vulnerability-scanner container sensor (DaemonSet) ─► findings exporter ─► Prometheus
   └─ Logs ─► Loki ─► Grafana
Networks: management segment, security segment, isolated attack segment without uplink
```

## Design decisions

| Decision | Why |
|---|---|
| Least privilege for endpoint software | The less an agent is allowed to do, the less an attacker who controls the server can do with it |
| mTLS from endpoints to an edge gateway, pinned CA, fail closed | Endpoints never talk to internal services directly; a broken or substituted certificate stops traffic instead of downgrading |
| Existing EDR as an event source | The estate already ran an enterprise EDR; its events feed the same telemetry pipeline instead of being replaced |
| Vulnerability findings as Prometheus metrics | Findings become something you alert and graph on, next to availability, instead of a separate portal nobody opens |
| Alertmanager through an internal mail relay | Alerts must work without internet egress |
| Isolated attack segment with no uplink | Simulated attacks can never leak out |

## Implementation highlights

- Ansible playbook installing node_exporter on every Linux host in the lab.
- Kustomize-managed monitoring stack: Prometheus, Grafana, Loki, Promtail, Alertmanager,
  with exporters for both hypervisor platforms.
- A container vulnerability sensor as a DaemonSet plus a small custom exporter turning its
  findings into Prometheus metrics.
- EDR rollout and integration across Windows and Linux endpoints: agent deployment,
  management-server connectivity, firewall paths, and troubleshooting.
- Secrets for exporters and the mail relay created at deploy time, never committed; only
  example files in Git.

## Security controls

- Network segmentation by function, with explicit firewall paths between segments.
- Least-privilege service accounts and read-only API tokens for exporters.
- mTLS and certificate pinning on the telemetry channel.
- Central logs and metrics as evidence for incident response.

## Failure scenarios and troubleshooting

| Symptom | Root cause | Fix |
|---|---|---|
| A test VM could not reach anything after a template clone | Its NIC sat on the isolated segment's bridge | Remap the NIC; make the bridge an explicit per-role template parameter |
| Endpoint traffic failed after a certificate rotation | Pinned-CA clients rejected the new chain, as designed | Rotate the trust bundle before the leaf certificates; stage rollouts |
| Hypervisor memory alerts did not match reality | Reported memory included cache, and ballooning skewed guest numbers | Alert on available memory, not used percentage; disable ballooning where it hurts scheduling |
| Alerts silently not delivered | No egress for an external mail provider | Internal relay with its own TLS and credentials |

## Lessons learned

1. Security tooling is infrastructure: it needs monitoring, capacity planning and change
   control like everything else.
2. Grant endpoint software the minimum it needs.
3. Put security findings where operators already look.
4. Segment first, then allow. Retrofitting segmentation is far harder.

## Public evidence

| Professional pattern | Reconstruction in this repo |
|---|---|
| Commercial enterprise EDR | Wazuh single-node on the security VLAN, pinned upstream release ([security/wazuh](../security/wazuh/wazuh.sh)) |
| Commercial container vulnerability scanning | Trivy image/filesystem/config scanning and SBOM in CI ([scripts/scan.sh](../scripts/scan.sh)) |
| node_exporter on every host | [ansible/roles/node-exporter](../ansible/roles/node-exporter) (checksum-pinned, sandboxed systemd unit) |
| Monitoring stack + alerting | [observability-stack chart](../kubernetes/helm/observability-stack) with SLO alerts and runbooks |
| Network segmentation | [docs/network-design.md](../docs/network-design.md), nftables in [linux-hardening](../ansible/roles/linux-hardening), NetworkPolicy, Cilium + Hubble |
| Host hardening | [ansible/roles/linux-hardening](../ansible/roles/linux-hardening), Molecule-tested |

## 中文摘要

讓地端實驗室像一個小型企業環境：Windows/Linux 端點部署商用企業級 EDR、以商用弱點管理平台掃描主機與容器、集中監控與告警，並建立收集端點遙測的管線。關鍵設計：端點軟體最小權限、端點到 edge gateway 走 mTLS 並 pin CA（失敗即關閉）、把弱點發現轉成 Prometheus 指標、告警走內部郵件中繼、攻擊模擬網段完全無對外連線。本 repo 以 Wazuh、Trivy、node_exporter、可觀測性 umbrella chart 與 Cilium/Hubble 開源重建相同模式。
