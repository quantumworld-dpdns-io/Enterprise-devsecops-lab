# VM-based lab on a Proxmox host: the same topology as the local environment, on real VMs.
#   terraform apply                   -> VMs
#   ansible-playbook playbooks/site.yml -> hardening, k3s, runner (inventory rendered below)
#
# Credentials come from the environment, never from files in this repo:
#   PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (user@realm!token=secret)

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Shared state with locking for a team. Example for an S3-compatible store:
  # backend "s3" {
  #   bucket                      = "tfstate-lab"
  #   key                         = "proxmox/terraform.tfstate"
  #   region                      = "eu-central-1"
  #   use_lockfile                = true
  # }
}

provider "proxmox" {
  # Lab hypervisors often run a self-signed certificate. Set PROXMOX_VE_INSECURE=false
  # once the API certificate is issued by a CA the workstation trusts.
  insecure = var.proxmox_insecure
}

locals {
  vms = {
    "k3s-server-1" = { id = 210, role = "k3s-server", ip = "10.10.10.10", cores = 2, mem = 4096, net = "mgmt" }
    "k3s-agent-1"  = { id = 211, role = "k3s-agent", ip = "10.10.10.11", cores = 4, mem = 8192, net = "mgmt" }
    "k3s-agent-2"  = { id = 212, role = "k3s-agent", ip = "10.10.10.12", cores = 4, mem = 8192, net = "mgmt" }
    "runner-1"     = { id = 220, role = "runner", ip = "10.10.10.20", cores = 4, mem = 8192, net = "mgmt" }
    "sec-vm-1"     = { id = 230, role = "security", ip = "192.168.100.10", cores = 4, mem = 8192, net = "security" }
  }

  networks = {
    mgmt     = { cidr = "10.10.10.0/24", gateway = "10.10.10.1", vlan = var.mgmt_vlan }
    security = { cidr = "192.168.100.0/24", gateway = "192.168.100.1", vlan = var.security_vlan }
  }
}

module "vm" {
  source   = "../../modules/proxmox-vm"
  for_each = local.vms

  name            = each.key
  role            = each.value.role
  node_name       = var.proxmox_node
  vm_id           = each.value.id
  template_id     = var.template_id
  cores           = each.value.cores
  memory_mb       = each.value.mem
  bridge          = var.bridge
  vlan_id         = local.networks[each.value.net].vlan
  ipv4_cidr       = "${each.value.ip}/${split("/", local.networks[each.value.net].cidr)[1]}"
  gateway         = local.networks[each.value.net].gateway
  dns_servers     = var.dns_servers
  ssh_public_keys = var.ssh_public_keys
}

# Hand-off to Ansible: render the inventory from what Terraform actually created.
resource "local_file" "inventory" {
  filename        = "${path.module}/../../../ansible/inventory/proxmox.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/inventory.yml.tftpl", {
    servers  = { for k, m in module.vm : k => m.ipv4 if m.role == "k3s-server" }
    agents   = { for k, m in module.vm : k => m.ipv4 if m.role == "k3s-agent" }
    runners  = { for k, m in module.vm : k => m.ipv4 if m.role == "runner" }
    security = { for k, m in module.vm : k => m.ipv4 if m.role == "security" }
  })
}
