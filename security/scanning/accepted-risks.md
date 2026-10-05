# Accepted risks

Scanners report findings; this file records the ones deliberately **not** fixed, why, who
decided, and when the decision expires. A risk without a review trigger becomes a permanent
blind spot, so every row needs one.

Machine-readable suppressions live next to the tool (`.trivyignore`, `.checkov.yaml`). Each
suppression there must point back to a row here.

| ID | Finding | Scope | Reason | Owner | Review when |
|---|---|---|---|---|---|
| AR-001 | k3s node containers run `privileged` | `terraform/modules/k3s-docker-cluster` | Running kubelet and containerd inside Docker requires it. This is the local/CI environment only; the Proxmox environment runs k3s on real VMs. | Dennis Lee | If the local env moves to a VM-based runtime |
| AR-002 | Self-signed lab root CA | `kubernetes/platform/base/lab-ca.yaml` | No public trust is needed inside an isolated lab. Production overlays swap the issuer for an enterprise PKI or ACME. | Dennis Lee | Before any internet-facing deployment |
| AR-003 | Local Terraform state | `terraform/environments/local` | The local environment is disposable and holds no shared state. Remote state with locking is described in `docs/deployment.md`. | Dennis Lee | When a second operator or a shared environment appears |
| AR-005 | No Docker `HEALTHCHECK` in the app image | `app/Dockerfile` | The distroless image has no shell or curl by design. Kubernetes liveness, readiness and startup probes cover health. | Dennis Lee | If the image runs outside Kubernetes |
| AR-004 | Chart default references the image by tag, not digest | `kubernetes/helm/demo-app/values.yaml` | The digest only exists after CI pushes and signs the image, so CI passes `image.digest` at deploy time. The local overlay imports images built in the same run. | Dennis Lee | Never relaxed for shared environments |
| AR-006 | `imagePullPolicy: IfNotPresent` instead of `Always` | `kubernetes/helm/demo-app` | Tags are immutable and deploys pin digests, so a cached image is the same image. `Always` makes every restart depend on registry availability. | Dennis Lee | If mutable tags are ever allowed |
