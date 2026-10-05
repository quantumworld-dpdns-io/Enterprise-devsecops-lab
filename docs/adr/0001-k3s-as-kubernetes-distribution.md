# ADR 0001: k3s as the Kubernetes distribution

- **Status**: accepted
- **Context**: The platform targets on-premises hardware and small VM footprints, and the
  same cluster must run on a laptop and in CI. Upstream kubeadm needs more moving parts
  (etcd, CNI, ingress, storage) before it runs a workload.
- **Decision**: k3s. One binary, embedded datastore, bundled Traefik, local-path storage and
  a network-policy controller. Secrets encryption is turned on at install.
- **Consequences**:
  - The control-plane components are not separate scrape targets, so their Prometheus
    jobs are disabled to avoid permanent false alerts.
  - The same Ansible role installs it on VMs, pinned by version and sha256.
  - Moving to EKS or AKS keeps all Kubernetes-level manifests unchanged; only the cluster
    layer (Terraform module) differs.
