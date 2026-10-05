# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/dennislee928/enterprise-devsecops-lab/security/advisories/new)
for this repository. Do not open a public issue.

Include what you found, how to reproduce it, and the impact you expect.

## What to expect

| Step | Target |
|---|---|
| Acknowledgement | within 3 working days |
| Initial assessment and severity (CVSS v4) | within 10 working days |
| Fix for critical/high findings | within 30 days of confirmation |
| Public advisory | after a fix is available, coordinated with the reporter |

Reporters are credited in the advisory unless they prefer otherwise.

## Scope

In scope: everything in this repository, including the demo service, container image,
Helm charts, Terraform, Ansible and CI workflows.

Out of scope: findings that require a compromised workstation or cluster-admin access,
and third-party components (report those upstream; tell us if they affect this repo).

## Supported versions

Only the latest commit on `main` and the most recent signed image are supported.

## Verifying what you run

Every image published from `main` is signed (cosign, keyless) and carries SBOM and SLSA
provenance attestations. See [docs/deployment.md](docs/deployment.md#verify-an-image).
