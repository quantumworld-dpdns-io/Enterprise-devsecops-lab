# Troubleshooting log

Real failures hit while building this lab, with the cause and the fix. Kept because the
reasoning is more useful than the final configuration.

## Platform

### node-exporter: `path "/" is mounted on "/" but it is not a shared or slave mount`
- **Where**: local runtime (k3s nodes are Docker containers).
- **Cause**: node-exporter mounts the host root with `HostToContainer` propagation, which
  needs a shared mount. Inside a container, `/` is private.
- **Fix**: `hostRootFsMount.enabled: false` for the local runtime only. Real VMs keep it.

### Cilium: `path "/var/run/netns" is mounted on "/var/run" but it is not a shared or slave mount`
- **Cause**: same family. The node containers mount `/run` and `/var/run` as private tmpfs.
- **Fix**: `scripts/cilium.sh` runs `mount --make-rshared /` and prepares bpffs and cgroup2
  on each node before installing Cilium. Disabled Cilium's auto-mounts accordingly.

### A rebuilt image did not roll out
- **Symptom**: a fix was built and imported, `helm upgrade` succeeded, old behaviour remained.
- **Cause**: the tag was `demo-app:dev`. Same tag, identical Deployment spec, so no rollout.
- **Fix**: every build gets a content-derived tag (`sha-<image id>`). This is also why the
  accepted-risk register allows `IfNotPresent` only with immutable tags.

### Helm release stuck in `pending-install`
- **Cause**: an install was interrupted while waiting.
- **Fix**: `helm uninstall` the stuck release, fix the cause, reinstall. Never retry on top of
  a pending release.

### Prometheus verification failed right after deploy
- **Cause**: a new ServiceMonitor needs a config reload plus one scrape interval.
- **Fix**: the check polls with a timeout instead of one fixed sleep.

## Supply chain and network

### `x509: certificate signed by unknown authority` pulling charts and templates
- **Where**: a corporate network with a TLS-intercepting proxy.
- **Cause**: containers do not trust the proxy's CA. Hosts outside GitHub (for example the
  cert-manager chart repo) worked; GitHub-hosted release assets did not.
- **Fix**: download through the host's trusted curl into a pinned local cache
  (`scripts/charts.sh fetch`, `CURL=curl.exe`). No one's CA trust had to change.
- **Windows detail**: schannel then failed with `CRYPT_E_NO_REVOCATION_CHECK` because the
  proxy certificate's CRL was unreachable. `--ssl-revoke-best-effort` keeps chain validation
  and only skips revocation when the endpoint cannot be reached.

### Nuclei ran with zero templates
- **Cause**: `-disable-update-check` also disables the template download, and the download
  goes to GitHub anyway.
- **Fix**: pinned template release fetched into a cache and mounted read-only. The stage
  fails if Nuclei cannot run, so it never passes silently.

## Security findings fixed

### DAST: Prometheus metrics reachable through the ingress (Nuclei `prometheus-metrics`, medium)
- **Fix**: split the app into a public listener (API only) and an admin listener (probes,
  metrics). The ingress routes only the public port; NetworkPolicy opens the admin port to
  `monitoring` only. e2e now asserts `/metrics`, `/healthz` and `/readyz` return 404 publicly.
- **Follow-up found by ZAP**: routing only `/api` made Traefik's own 404 pages lack HSTS.
  Routing every path to the app, which 404s with full security headers, fixed it.

### Checkov on the rendered chart: default namespace, pull policy, digest
- **Fix**: templates set `metadata.namespace`. Pull policy and digest pinning are documented
  decisions (AR-004, AR-006). The earlier false alarm came from scanning a stale render;
  the Checkov step now renders first.

## Configuration management

### Molecule: `Missing privilege separation directory: /run/sshd`
- **Cause**: `sshd -t` validation needs `/run/sshd`, which exists only after sshd has run
  once. Fresh cloud images hit this on first boot.
- **Fix**: the role creates the directory before validating. Found by Molecule; a real
  first-run bug, not a test artefact.

### ansible-lint took more than ten minutes
- **Cause**: it was linting the installed collections directory.
- **Fix**: `.ansible-lint` excludes `.collections/`.

### A vault example in `group_vars/` passed validation
- **Cause**: Ansible loads every file in `group_vars/<group>/`, so the placeholder token in
  `vault.example.yml` was loaded as a real value and satisfied the length check.
- **Fix**: examples live in `ansible/examples/`, outside `group_vars`.

## demo-app runbooks

### demo-app-errors
`DemoAppHighErrorRate`: check `kubectl -n demo logs deploy/demo-app`, the Grafana
"demo-app - golden signals" dashboard, then traces in Tempo for failing requests.

### demo-app-latency
`DemoAppSlow`: compare p95 by route; check CPU throttling (`container_cpu_cfs_throttled_seconds_total`).

### demo-app-down
`DemoAppDown`: `kubectl -n demo get pods,endpoints`; check the admin port NetworkPolicy
still allows `monitoring`.
