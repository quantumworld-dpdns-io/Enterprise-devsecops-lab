# ADR 0002: GitOps with Argo CD, Helm for packaging, Kustomize for environment overlays

- **Status**: accepted
- **Context**: Clusters drifted when changes were applied by hand, and it was not always
  clear which revision was running. Packaging needed to be reusable across environments.
- **Decision**:
  - Argo CD with an app-of-apps root and one Application per component.
  - Two AppProjects: `platform` (may create CRDs, cluster roles, webhooks) and `lab`
    (namespaced workloads in listed namespaces only).
  - Own Helm charts for things we ship (`demo-app`, the `observability-stack` umbrella);
    Kustomize for small platform manifests with per-environment overlays.
  - `selfHeal: true` everywhere; `prune: false` for the CNI and for namespaces.
- **Consequences**:
  - Anything not in Git gets reverted. This is verified: a managed NetworkPolicy deleted by
    hand is restored by Argo CD (`scripts/argocd-verify.sh`).
  - Secrets that must be random (the Grafana admin password) stay out of charts, because a
    chart-generated random value changes on every render and causes permanent drift.
  - The CNI cannot be bootstrapped by Argo CD (Argo CD needs pod networking). It is
    installed once by script and adopted by Argo CD afterwards.
