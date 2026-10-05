package main

import rego.v1

good_deploy := {
	"kind": "Deployment",
	"metadata": {"name": "ok"},
	"spec": {"template": {"spec": {
		"automountServiceAccountToken": false,
		"securityContext": {"runAsNonRoot": true},
		"containers": [{
			"name": "app",
			"image": "registry.lab.example/app:1.2.3",
			"resources": {"limits": {"cpu": "100m", "memory": "64Mi"}},
			"securityContext": {
				"allowPrivilegeEscalation": false,
				"readOnlyRootFilesystem": true,
				"capabilities": {"drop": ["ALL"]},
			},
		}],
	}}},
}

test_good_deployment_passes if {
	count(deny) == 0 with input as good_deploy
}

test_latest_tag_denied if {
	bad := json.patch(good_deploy, [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "app:latest"}])
	some msg in deny with input as bad
	contains(msg, ":latest")
}

test_root_denied if {
	bad := json.patch(good_deploy, [{"op": "remove", "path": "/spec/template/spec/securityContext/runAsNonRoot"}])
	some msg in deny with input as bad
	contains(msg, "may run as root")
}

test_missing_limits_denied if {
	bad := json.patch(good_deploy, [{"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits"}])
	count(deny) >= 2 with input as bad
}

test_privileged_denied if {
	bad := json.patch(good_deploy, [{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/privileged", "value": true}])
	some msg in deny with input as bad
	contains(msg, "privileged")
}

test_host_network_denied if {
	bad := json.patch(good_deploy, [{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}])
	some msg in deny with input as bad
	contains(msg, "hostNetwork")
}

test_ingress_without_tls_denied if {
	some msg in deny with input as {"kind": "Ingress", "metadata": {"name": "web"}, "spec": {"rules": []}}
	contains(msg, "no TLS")
}
