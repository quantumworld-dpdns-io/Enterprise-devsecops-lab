# Case study 2: Self-hosted DevSecOps platform

*An NDA-safe write-up. Project names, group paths, hostnames and rule contents are omitted.*

## Problem

Several repositories (Go services, Python data pipelines, a TypeScript front end and
cross-platform client builds) each had their own ad-hoc CI. Security
scanning was inconsistent: some repositories scanned images, few produced SBOMs, none
enforced policy. Findings that nobody acted on piled up until people ignored the scanner.

## Context

- Self-hosted GitLab with self-managed runners on the internal network; some repositories
  also built on GitHub Actions (multi-OS builds).
- Outbound TLS inspected by the corporate firewall.
- Branch flow with development, staging and main branches.

## Architecture

```text
Developer ─► GitLab merge request
               │
               ▼
        project .gitlab-ci.yml ──include──► shared security CI template (one project)
               │
   secrets ─► build ─► test ─► prepare ─► policy ─► threat-model ─► SBOM ─► image scan ─► notify
               │                                                     │
               ▼                                                     ▼
          self-managed runners                           findings report + notification
```

- **One shared template, included by every product repository.** A fix to a scanner job
  reached all repositories in one merge.
- **Stages**: secret scanning; SAST (Semgrep with custom rules for Terraform and Kubernetes
  YAML, gosec); dependency and image scanning (Trivy, govulncheck); SBOM (Syft); policy
  (OPA/conftest, Checkov, tflint); a threat-model stage; a notification job.
- **GitHub Actions** for the cross-platform builds, with OpenSSF Scorecard, Snyk,
  coverage upload and golangci-lint.

## Design decisions

| Decision | Why |
|---|---|
| Central template via `include` | One place to fix, one place to upgrade scanner versions |
| Delta gate, not "zero findings" | A permanently red pipeline gets ignored. The gate fails on new, fixable findings; known items live in a machine-readable baseline plus a human-readable accepted-risk register |
| Policy `deny` only for controls truly in force | The threat model marks controls as done or planned. Done becomes `deny`, planned is `warn`, so the pipeline tells the truth about what is enforced |
| Threat model as a pipeline input | Changes that touch a trust boundary must update the model; the stage checks it exists and is current |

## Implementation highlights

- A runner fleet with health checks, documented registration and a restricted executor.
- Secret-scanning scripts that keep plaintext credentials out of tracked files, with
  matching variable names required between `.env` files and CI variables.
- OWASP CI/CD Top 10 detection rules for pipeline configuration itself, for example
  unpinned images or dangerous triggers.

## Security controls

- Secrets never in the repository; masked and protected CI variables.
- Pinned scanner images; scanner upgrades are deliberate merges.
- Accepted risks recorded with who decided and when to re-evaluate.

## Failure scenarios and troubleshooting

| Symptom | Root cause | Fix |
|---|---|---|
| Pipelines on feature branches failed before any job ran | GitLab resolves `include:` before `workflow:rules`, and resolves a cross-project include with the permissions of the user who triggered the pipeline | Gate the include itself with rules matching the branches that run pipelines; grant read access to the template project |
| Runner jobs failed TLS handshakes to public registries and Git hosts | Firewall TLS inspection; job containers did not trust the inspection CA | A decision for the security owner: trust the inspection CA explicitly in the runner, or route those fetches differently. Never disable verification |
| Scanner finding counts climbed and were ignored | The gate failed on every finding, including unfixable upstream CVEs | Delta gate + baseline + accepted-risk register with review triggers |
| Jobs that start sibling containers could not see the checkout | The Docker-socket pattern mounts paths from the host, not from the job container | Bind the builds directory at the same path on host and job container |

## Lessons learned

1. Make the secure path the default path. A shared template beat documentation.
2. Gates must be trustworthy, or people route around them.
3. Policy-as-code works best when it is honest about what is enforced today.
4. Know your CI system's evaluation order. Most "mysterious" pipeline failures were ordering.

## Public evidence

| Professional pattern | Reconstruction in this repo |
|---|---|
| Shared scan steps across platforms | [scripts/scan.sh](../scripts/scan.sh) called by both [GitHub Actions](../.github/workflows/ci.yml) and [GitLab CI](../.gitlab-ci.yml) |
| Self-hosted GitLab + runner | [gitlab/](../gitlab) (CE + Docker-executor runner), [ansible/roles/gitlab-runner](../ansible/roles/gitlab-runner) |
| Delta gate + accepted risks | [security/scanning/accepted-risks.md](../security/scanning/accepted-risks.md), `.checkov.yaml` |
| Threat model ↔ policy | [docs/threat-model.md](../docs/threat-model.md), [security/policy](../security/policy) |
| SBOM | Syft CycloneDX in CI |

Added in the public lab beyond the professional setup: keyless signing, SLSA provenance,
admission-time verification, DAST (ZAP and Nuclei), and OIDC-only cloud access from CI.

## 中文摘要

多個產品 repo 各自為政的 CI 與不一致的資安掃描，整併為一個由所有專案 `include` 的共用安全 CI 樣板：secrets → build → test → prepare → policy → threat-model → SBOM → image scan → notify。以 delta gate 加基準檔與接受風險登錄取代「零發現」，讓管線可信而不被忽略；OPA 政策只對真正落實的控制 `deny`、規劃中的用 `warn`。本 repo 以同一套 `scripts/scan.sh` 同時跑在 GitHub Actions 與 GitLab CI，並補上簽章、SLSA provenance、admission 驗簽與 DAST。
