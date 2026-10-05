# ADR 0004: Cilium (eBPF) as the CNI option, flannel as the default

- **Status**: accepted
- **Context**: k3s defaults to flannel plus kube-router for NetworkPolicy. That enforces
  policy but gives no visibility into what was dropped and why. Debugging a deny meant
  guessing.
- **Decision**: keep flannel as the zero-dependency default, and offer Cilium through a
  Terraform variable (`cni = "cilium"`). Cilium runs with Hubble relay and UI. kube-proxy
  stays for now; kube-proxy replacement is the next step once the eBPF service path is
  validated on the target kernels.
- **Consequences**:
  - The same NetworkPolicies and the same e2e tests pass on both CNIs.
  - Hubble records each policy drop with source, destination and verdict; the lab's verify
    step asserts that a blocked probe appears as `Policy denied DROPPED`.
  - Node containers need bpffs, a cgroup2 mount and shared mount propagation; real VMs do not.
  - On AKS the same choice is made natively (Azure CNI powered by Cilium).
