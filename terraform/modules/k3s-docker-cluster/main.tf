# k3s cluster where every node is a privileged Docker container.
# Same idea as k3d, written explicitly so each moving part is visible:
# a dedicated bridge network, a shared join token, one server, N agents.

resource "random_password" "token" {
  length  = 48
  special = false
}

resource "docker_network" "lab" {
  name   = "${var.cluster_name}-net"
  driver = "bridge"
  ipam_config {
    subnet  = var.network_cidr
    gateway = cidrhost(var.network_cidr, 1)
  }
}

resource "docker_image" "k3s" {
  name         = var.k3s_image
  keep_locally = true
}

resource "docker_volume" "server" {
  name = "${var.cluster_name}-server-1-data"
}

locals {
  server_name = "${var.cluster_name}-server-1"
  server_ip   = cidrhost(var.network_cidr, 10)

  server_args = concat(
    [
      "server",
      "--tls-san=127.0.0.1",
      "--tls-san=${local.server_ip}",
      "--cluster-cidr=${var.pod_cidr}",
      "--service-cidr=${var.service_cidr}",
      "--node-label=lab.example/role=control-plane",
      # The control plane runs system components only; workloads go to agents.
      "--node-taint=node-role.kubernetes.io/control-plane=true:NoSchedule",
      "--write-kubeconfig-mode=0600",
      "--secrets-encryption",
    ],
    var.cni == "cilium" ? ["--flannel-backend=none", "--disable-network-policy"] : [],
    var.extra_server_args,
  )
}

resource "docker_container" "server" {
  name       = local.server_name
  hostname   = local.server_name
  image      = docker_image.k3s.image_id
  privileged = true
  restart    = "unless-stopped"
  command    = local.server_args

  env = [
    "K3S_TOKEN=${random_password.token.result}",
  ]

  networks_advanced {
    name         = docker_network.lab.name
    ipv4_address = local.server_ip
  }

  # Only the API and the ingress entrypoints are published, all on loopback.
  ports {
    internal = 6443
    external = var.api_port
    ip       = "127.0.0.1"
  }
  ports {
    internal = 80
    external = var.http_port
    ip       = "127.0.0.1"
  }
  ports {
    internal = 443
    external = var.https_port
    ip       = "127.0.0.1"
  }

  tmpfs = {
    "/run"     = ""
    "/var/run" = ""
  }

  volumes {
    volume_name    = docker_volume.server.name
    container_path = "/var/lib/rancher/k3s"
  }

  labels {
    label = "lab.example/cluster"
    value = var.cluster_name
  }
}

resource "docker_volume" "agent" {
  count = var.agent_count
  name  = "${var.cluster_name}-agent-${count.index + 1}-data"
}

resource "docker_container" "agent" {
  count      = var.agent_count
  name       = "${var.cluster_name}-agent-${count.index + 1}"
  hostname   = "${var.cluster_name}-agent-${count.index + 1}"
  image      = docker_image.k3s.image_id
  privileged = true
  restart    = "unless-stopped"
  command = [
    "agent",
    "--node-label=lab.example/role=worker",
  ]

  env = [
    "K3S_URL=https://${local.server_ip}:6443",
    "K3S_TOKEN=${random_password.token.result}",
  ]

  networks_advanced {
    name         = docker_network.lab.name
    ipv4_address = cidrhost(var.network_cidr, 11 + count.index)
  }

  tmpfs = {
    "/run"     = ""
    "/var/run" = ""
  }

  volumes {
    volume_name    = docker_volume.agent[count.index].name
    container_path = "/var/lib/rancher/k3s"
  }

  labels {
    label = "lab.example/cluster"
    value = var.cluster_name
  }

  depends_on = [docker_container.server]
}
