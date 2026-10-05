# ADR 0003: Open-source equivalents for commercial security products

- **Status**: accepted
- **Context**: The professional environment this lab reconstructs used commercial products
  (an enterprise EDR, a vulnerability-management platform). They cannot be redistributed,
  and a public lab must not contain licence material or tenant configuration.
- **Decision**: replace each with an open-source tool that exercises the same integration
  pattern.

  | Professional environment | Public lab | Same pattern being shown |
  |---|---|---|
  | Commercial vulnerability-management platform (hosts and containers) | Trivy (image, filesystem, config), CycloneDX SBOM from Syft, Nuclei, OWASP ZAP | Continuous scanning, a fail gate on fixable findings, an accepted-risk register |
  | Commercial enterprise EDR (endpoint agents, management server) | Wazuh single-node on the security VLAN (`security/wazuh/wazuh.sh`, pinned upstream release); Cilium Hubble for network-flow visibility | Agents on every host, central collection, the security tooling isolated on its own network segment |
  | Commercial PKI | cert-manager private CA | Issuer chain, leaf certificates per service, rotation |

- **Consequences**: the lab shows architecture and integration capability, not access to a
  licence. Commercial products are described by category only.
