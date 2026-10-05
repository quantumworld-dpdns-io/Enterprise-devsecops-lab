package main

# Policy-as-code for rendered Kubernetes manifests (conftest >= 0.50, Rego v1).
# Each rule maps to a control in docs/threat-model.md. `deny` fails the pipeline;
# `warn` reports controls that are recommended but not yet enforced everywhere.

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob", "Pod"}

is_workload if workload_kinds[input.kind]

pod_spec := input.spec if input.kind == "Pod"

pod_spec := input.spec.jobTemplate.spec.template.spec if input.kind == "CronJob"

pod_spec := input.spec.template.spec if {
	input.kind != "Pod"
	input.kind != "CronJob"
}

name := sprintf("%s/%s", [input.kind, input.metadata.name])

containers contains c if some c in pod_spec.containers

containers contains c if some c in pod_spec.initContainers

# TM-K8S-01: workloads never run as root.
deny contains msg if {
	is_workload
	not pod_spec.securityContext.runAsNonRoot
	some c in containers
	not c.securityContext.runAsNonRoot
	msg := sprintf("%s: container %q may run as root (set runAsNonRoot)", [name, c.name])
}

# TM-K8S-02: no privilege escalation, no privileged containers.
deny contains msg if {
	is_workload
	some c in containers
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s: container %q must set allowPrivilegeEscalation=false", [name, c.name])
}

deny contains msg if {
	is_workload
	some c in containers
	c.securityContext.privileged == true
	msg := sprintf("%s: container %q is privileged", [name, c.name])
}

# TM-K8S-03: drop all Linux capabilities.
deny contains msg if {
	is_workload
	some c in containers
	not "ALL" in object.get(c, ["securityContext", "capabilities", "drop"], [])
	msg := sprintf("%s: container %q must drop ALL capabilities", [name, c.name])
}

# TM-K8S-04: resource limits bound the blast radius of a compromised or runaway pod.
deny contains msg if {
	is_workload
	some c in containers
	not c.resources.limits.memory
	msg := sprintf("%s: container %q has no memory limit", [name, c.name])
}

deny contains msg if {
	is_workload
	some c in containers
	not c.resources.limits.cpu
	msg := sprintf("%s: container %q has no cpu limit", [name, c.name])
}

# TM-SUP-01: images are immutable references, never :latest or untagged.
deny contains msg if {
	is_workload
	some c in containers
	not contains(c.image, "@sha256:")
	not regex.match(`:[A-Za-z0-9._-]+$`, c.image)
	msg := sprintf("%s: container %q image %q has no tag or digest", [name, c.name, c.image])
}

deny contains msg if {
	is_workload
	some c in containers
	endswith(c.image, ":latest")
	msg := sprintf("%s: container %q uses the mutable :latest tag", [name, c.name])
}

# TM-K8S-05: no host namespaces.
deny contains msg if {
	is_workload
	some field in ["hostNetwork", "hostPID", "hostIPC"]
	pod_spec[field] == true
	msg := sprintf("%s: %s is not allowed", [name, field])
}

# TM-K8S-06: the API token is mounted only when the workload needs it.
warn contains msg if {
	is_workload
	not pod_spec.automountServiceAccountToken == false
	msg := sprintf("%s: automountServiceAccountToken is not disabled", [name])
}

# TM-K8S-07: read-only root filesystem.
warn contains msg if {
	is_workload
	some c in containers
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("%s: container %q root filesystem is writable", [name, c.name])
}

# TM-SUP-02: production images should be pinned by digest.
warn contains msg if {
	is_workload
	some c in containers
	not contains(c.image, "@sha256:")
	msg := sprintf("%s: container %q image is not pinned by digest", [name, c.name])
}

# TM-NET-01: every Ingress terminates TLS.
deny contains msg if {
	input.kind == "Ingress"
	count(object.get(input.spec, "tls", [])) == 0
	msg := sprintf("%s: Ingress has no TLS section", [name])
}
