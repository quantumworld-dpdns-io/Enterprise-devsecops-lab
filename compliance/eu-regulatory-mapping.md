# EU regulatory mapping: CRA, NIS2, DORA

This maps the technical evidence in this repository to three EU regulations, with an honest
gap status per requirement. It is an engineering self-assessment, not legal advice or an audit.

**Status legend**

| Mark | Meaning |
|---|---|
| ✅ | Implemented in this repository and verified by an automated check |
| 🔶 | Partially implemented, or implemented as design/IaC without an automated check |
| ❌ | Gap. Usually an organisational process that code alone cannot satisfy |

**Scope.** The "product" for the CRA view is the demo service and its container image. The
"entity" for the NIS2 and DORA views is a hypothetical operator running this platform.
Organisational obligations (management accountability, regulator reporting, training, HR)
are listed so the gaps are visible, not because a lab could close them.

**Timelines worth knowing**

| Regulation | Applies |
|---|---|
| NIS2, Directive (EU) 2022/2555 | National transposition deadline 17 Oct 2024; obligations via national law |
| DORA, Regulation (EU) 2022/2554 | Since 17 Jan 2025 (financial entities and their critical ICT providers) |
| CRA, Regulation (EU) 2024/2847 | Vulnerability/incident reporting from 11 Sep 2026; all other obligations from 11 Dec 2027 |

---

## 1. Cyber Resilience Act, Annex I

### Part I: essential cybersecurity requirements of the product

| Req. | Requirement (summarised) | Evidence in this repo | Status |
|---|---|---|---|
| I.1 | Security level appropriate to the risks | Threat model per trust boundary drives controls and policy-as-code ([threat-model.md](../docs/threat-model.md), [kubernetes.rego](../security/policy/kubernetes.rego)) | ✅ |
| I.2(a) | No known exploitable vulnerabilities at release | Trivy fs + image scan, govulncheck, fail on fixable HIGH/CRITICAL in CI; accepted-risk register | ✅ |
| I.2(b) | Secure by default configuration | Non-root distroless image, read-only rootfs, all capabilities dropped, default-deny NetworkPolicy, restricted Pod Security; enforced by conftest `deny` rules | ✅ |
| I.2(c) | Vulnerabilities addressable through security updates | Immutable content-derived tags, signed images, GitOps rollout; automatic patch channel on AKS | 🔶 No user-facing update notification mechanism |
| I.2(d) | Protection from unauthorised access | Separate admin listener, NetworkPolicy allow-lists, Entra ID-only AKS, EKS access entries, IMDSv2 hop limit 1 | ✅ |
| I.2(e) | Confidentiality of data (at rest and in transit) | TLS at ingress from a private CA, KMS envelope encryption of Kubernetes Secrets (EKS, AKS), encrypted S3/EBS/log groups | ✅ |
| I.2(f) | Integrity of data, commands, programs and configuration | Cosign keyless signatures, SLSA provenance, Kyverno admission verification, Git as source of truth with Argo CD self-heal | ✅ |
| I.2(g) | Data minimisation | The demo service processes no personal data | 🔶 Not applicable to the demo; no data inventory process |
| I.2(h) | Availability, resilience against DoS | HPA, PodDisruptionBudget, topology spread, resource limits, graceful drain, multi-AZ node pools | 🔶 No rate limiting at the ingress yet |
| I.2(i) | Minimise impact on other services | Resource limits, per-workload egress policy, PSA restricted | ✅ |
| I.2(j) | Limit attack surface | Only `/api` served publicly; probes and metrics on a non-routed admin port (regression-tested after a Nuclei finding); distroless image without a shell | ✅ |
| I.2(k) | Reduce impact of incidents (exploitation mitigation) | seccomp RuntimeDefault, no privilege escalation, read-only rootfs, no service-account token | ✅ |
| I.2(l) | Record and monitor security-relevant activity | Kubernetes API audit policy (k3s role), EKS control-plane audit logs, Container Insights, Loki log pipeline, Hubble flow logs, SLO alerts | 🔶 Logs collected, no SIEM correlation rules shipped here |
| I.2(m) | Secure and easy deletion of data and settings | Lifecycle rules on S3, retention limits on Loki/Tempo | ❌ No user-facing data deletion feature |

### Part II: vulnerability handling requirements of the manufacturer

| Req. | Requirement (summarised) | Evidence in this repo | Status |
|---|---|---|---|
| II.1 | Identify and document vulnerabilities and components, including an SBOM | Syft CycloneDX SBOM per build, attached to the image as a signed attestation; uploaded as a CI artifact | ✅ |
| II.2 | Address and remediate vulnerabilities without delay | CI gate on fixable HIGH/CRITICAL; accepted-risk register with owner and review trigger | 🔶 No remediation SLA defined |
| II.3 | Regular tests and reviews | SAST (Semgrep, gosec), SCA, IaC scanning, DAST (ZAP, Nuclei) and e2e on every main build | ✅ |
| II.4 | Disclose fixed vulnerabilities publicly | [SECURITY.md](../SECURITY.md): public GitHub advisory after a fix | 🔶 Process defined, not yet exercised |
| II.5 | Coordinated vulnerability disclosure policy | [SECURITY.md](../SECURITY.md) with response targets | ✅ |
| II.6 | Facilitate information sharing, provide a contact address | Private vulnerability reporting channel in [SECURITY.md](../SECURITY.md) | ✅ |
| II.7 | Secure distribution of updates | Signed images, provenance, admission verification; registry access via OIDC, no static keys | ✅ |
| II.8 | Security updates disseminated without delay and free of charge | — | ❌ Organisational/commercial obligation |
| Art. 14 | Report actively exploited vulnerabilities (24h early warning) | — | ❌ No reporting runbook or ENISA single reporting platform account |

---

## 2. NIS2, Article 21(2): cybersecurity risk-management measures

| Art. 21(2) | Measure | Evidence in this repo | Status |
|---|---|---|---|
| (a) | Risk analysis and information-system security policies | STRIDE threat model per trust boundary, controls mapped to policy rules, accepted-risk register | 🔶 Technical policy only; no board-approved ISMS policy |
| (b) | Incident handling | Alerting rules with runbook links, centralised logs and traces, Hubble drop visibility | 🔶 No incident response plan, roles or exercise record |
| (c) | Business continuity, backup, disaster recovery, crisis management | Everything reproducible from Git (IaC + GitOps); S3 versioning; multi-AZ designs | ❌ No backup/restore of stateful data tested (e.g. Velero), no RTO/RPO |
| (d) | Supply chain security | Pinned charts/images/tools, SBOM, cosign + SLSA provenance, Kyverno verification, registry allow-list | ✅ |
| (e) | Security in acquisition, development and maintenance, incl. vulnerability handling | Secure SDLC pipeline on GitHub and GitLab (secrets, SAST, SCA, IaC, policy, DAST); protected-environment apply via OIDC | ✅ |
| (f) | Assessing effectiveness of measures | e2e tests prove controls (NetworkPolicy deny with positive control, PSA rejection, TLS issuer, header checks, self-heal) | ✅ |
| (g) | Basic cyber hygiene and training | Linux hardening role (SSH, sysctl, nftables, auditd, auto-updates), molecule-tested | 🔶 No training programme |
| (h) | Cryptography and encryption policies | Private CA via cert-manager, modern SSH ciphers, KMS with rotation, HSM-backed Key Vault keys | 🔶 No written crypto policy or key inventory |
| (i) | HR security, access control, asset management | Least-privilege IAM roles, Entra ID groups, Argo CD RBAC default read-only, tags for asset ownership | 🔶 No joiner/mover/leaver process |
| (j) | MFA / continuous authentication, secure communications | Entra ID-only AKS access (MFA enforceable by Conditional Access), SSH keys only, no static cloud keys | 🔶 MFA is a tenant policy outside this repo |
| Art. 23 | Incident reporting (24h / 72h / 1 month) | — | ❌ Reporting procedure and CSIRT contacts |

---

## 3. DORA: ICT risk management and related chapters

| Article | Requirement | Evidence in this repo | Status |
|---|---|---|---|
| 5 | Governance and organisation (management body accountable) | — | ❌ Organisational |
| 6 | ICT risk management framework, documented and reviewed | Threat model, accepted-risk register, ADRs | 🔶 Not a full framework |
| 7 | ICT systems, protocols and tools: reliable, adequate capacity, resilient | Resource requests/limits, HPA, PDB, priority-aware scheduling, multi-AZ | ✅ |
| 8 | Identification of ICT assets, functions and dependencies | IaC as asset inventory; tags (owner, cost-center, environment); SBOM per image | 🔶 No business-function mapping |
| 9 | Protection and prevention | Network segmentation, encryption, least privilege, patch channels, hardening | ✅ |
| 10 | Detection of anomalous activity | Prometheus SLO alerts, audit logs, Hubble drops, Container Insights | 🔶 No anomaly detection or SOC integration in this repo |
| 11 | Response and recovery | GitOps self-heal (verified), rolling updates with zero unavailable, graceful drain | 🔶 No response/recovery plans or tests |
| 12 | Backup, restoration and recovery | S3 versioning, IaC rebuild | ❌ No tested restore of stateful data |
| 13 | Learning and evolving (post-incident reviews) | Troubleshooting log of real failures and fixes ([troubleshooting.md](../docs/troubleshooting.md)) | 🔶 No formal post-incident review process |
| 14 | Communication | — | ❌ Organisational |
| 17–19 | ICT incident management, classification, major-incident reporting | Alerting and runbooks only | ❌ |
| 24–25 | Digital operational resilience testing programme | Automated vulnerability scanning, DAST, e2e and policy tests on every build | 🔶 No scenario-based or performance testing programme |
| 26 | Threat-led penetration testing (TLPT) | — | ❌ Applies to designated entities; external testers |
| 28–30 | ICT third-party risk, register of information, contract terms | Pinned third-party components with SBOM; cloud provider choice documented in ADRs | ❌ No register of information or contract review |

---

## 4. Gap summary and next steps

| Priority | Gap | Closes | Effort |
|---|---|---|---|
| 1 | Tested backup and restore of stateful components (Velero to object storage, quarterly restore drill) | NIS2 (c), DORA 11–12 | Medium |
| 2 | Incident response runbook with severity classification and the 24h/72h/1-month reporting timeline | NIS2 Art. 23, DORA 17–19, CRA Art. 14 | Medium |
| 3 | Ingress rate limiting and a load test in CI | CRA I.2(h), DORA 24–25 | Small |
| 4 | Remediation SLA per severity, measured from scanner findings | CRA II.2 | Small |
| 5 | Detection rules shipped to a SIEM, not only logs | CRA I.2(l), DORA 10 | Medium |
| 6 | Crypto policy and key inventory generated from IaC (KMS/Key Vault keys, rotation periods) | NIS2 (h) | Small |

### Cross-reference to ISO/IEC 27001:2022 Annex A

| Lab evidence | Annex A controls |
|---|---|
| Secure SDLC pipeline, SAST/SCA/DAST | 8.25 Secure development life cycle, 8.28 Secure coding, 8.29 Security testing |
| Vulnerability gates, accepted-risk register | 8.8 Management of technical vulnerabilities |
| IaC, GitOps, policy-as-code | 8.9 Configuration management, 8.32 Change management |
| Logs, metrics, traces, audit logs | 8.15 Logging, 8.16 Monitoring activities |
| KMS, private CA, TLS | 8.24 Use of cryptography |
| SBOM, signatures, provenance, pinned dependencies | 5.21 Managing information security in the ICT supply chain |
| NetworkPolicy, NSGs, segmentation | 8.20 Network security, 8.22 Segregation of networks |
| Least-privilege IAM, OIDC, no static keys | 5.15 Access control, 5.18 Access rights, 8.2 Privileged access rights |

---

## 中文摘要

本文件把本 repo 的技術證據對應到歐盟三項法規：CRA 附件 I（產品資安要求與漏洞處理）、NIS2 第 21(2) 條（十項資安風險管理措施）、DORA 第 5–30 條（ICT 風險管理、事件管理、韌性測試、第三方風險），並逐條標示 ✅ 已實作且有自動化驗證、🔶 部分達成、❌ 缺口。

技術面強項：安全預設組態、供應鏈安全（SBOM、cosign 簽章、SLSA provenance、admission 驗簽）、Secure SDLC 管線、加密與最小權限。主要缺口多屬組織流程：CVD 漏洞揭露政策、事件通報（NIS2 24h/72h/1 個月、CRA 第 14 條 24h 早期預警）、備份還原演練、事件應變計畫、第三方資訊登錄冊。第 4 節列出補強優先序。本文件為工程自評，非法律意見或稽核結論。
