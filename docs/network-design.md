# Network design

All addresses are documentation-style lab ranges. None correspond to a real environment.

## Address plan

| Network | CIDR | Used for |
|---|---|---|
| Management / node network | `10.10.10.0/24` | k3s nodes (`.10` server, `.11+` agents), runner `.20`, gateway `.1` |
| Second local cluster | `10.10.20.0/24` | A side-by-side cluster (for example the Cilium variant) |
| Pod network | `10.20.0.0/16` | k3s cluster CIDR (one /24 per node) |
| Service network | `10.21.0.0/16` | Kubernetes ClusterIP range |
| Security VLAN | `192.168.100.0/24` | Security tooling VM (`.10`), reachable from management through the firewall only |
| AWS VPC | `10.30.0.0/16` | Three private /20 subnets for nodes, three public /24 subnets for load balancers and NAT |
| Azure VNet | `10.40.0.0/16` | Node subnet `/20`; pods use the Azure CNI overlay range `10.244.0.0/16` |

## Segmentation layers

```text
Internet
   |
Firewall / NAT  ----  only 443 to the ingress nodes; management VLAN reachable from VPN only
   |
+--------------------------+----------------------------+
| VLAN 10  management      | VLAN 100  security          |
|  k3s-server-1  .10       |  sec-vm-1  192.168.100.10   |
|  k3s-agent-1/2 .11/.12   |  (Wazuh / scanners)         |
|  runner-1      .20       |                             |
+--------------------------+----------------------------+
```

Each layer only narrows what the layer above allowed:

1. **Perimeter firewall**: HTTPS to the ingress nodes, everything else denied. The security
   VLAN talks to management through explicit firewall rules only.
2. **Host firewall** (Ansible `linux-hardening`, nftables): default-drop inbound. Allow-lists
   per host group: SSH and node_exporter from management on every host; API server,
   kubelet, flannel VXLAN and ingress on k3s nodes; API server and kubelet from the pod CIDR.
3. **Kubernetes NetworkPolicy**: `default-deny-all` in workload namespaces, a shared DNS
   egress rule, and one policy per workload. The demo app allows its public port only from
   the ingress controller's namespace and its admin port only from `monitoring`.
4. **Cilium (optional CNI)**: the same policies enforced in eBPF, plus Hubble flow logs that
   record every drop with source, destination and reason.

## Ingress and TLS

- k3s ships Traefik. In the local runtime its service is published on host loopback
  (`127.0.0.1:8080/8443`), so nothing is exposed to the LAN.
- cert-manager runs a two-step private PKI: a self-signed bootstrap issuer mints the
  "Lab Example Root CA", and a CA issuer signs leaf certificates for every Ingress.
  Production swaps the CA issuer for the organisation's PKI or ACME.
- Every Ingress must have a TLS section; the Rego policy denies one without it.

## Egress through a TLS-intercepting proxy

Corporate networks often decrypt outbound TLS. Containers do not trust the proxy's CA, so
pulls from some hosts fail with `x509: certificate signed by unknown authority`. The lab
handles this without changing anyone's CA trust:

- Helm charts and Nuclei templates are downloaded by the host's curl into a local cache
  (`scripts/charts.sh fetch`, `CURL=curl.exe` on Windows) and installed from there.
- Charts are pinned in [kubernetes/charts.txt](../kubernetes/charts.txt), so the cache is
  exactly what CI would download.
- The GitLab Runner role accepts an optional proxy CA bundle, used only when the
  organisation has decided to trust that proxy.

## Cloud networking

- **EKS**: nodes only in private subnets; one NAT gateway in dev, one per AZ in production;
  an S3 gateway endpoint keeps image layer pulls off the NAT; flow logs for rejected traffic;
  the default security group is emptied; VPC CNI enforces NetworkPolicy.
- **AKS**: Azure CNI overlay with the Cilium dataplane, so Kubernetes NetworkPolicy is
  enforced in eBPF; an NSG on the node subnet allows only HTTPS from the internet; API
  server limited to authorized IP ranges, or private in production.
