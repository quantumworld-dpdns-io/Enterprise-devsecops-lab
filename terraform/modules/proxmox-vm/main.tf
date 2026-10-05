# One cloud-init VM cloned from a template. Ansible takes over once SSH is up.

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Managed by Terraform (enterprise-devsecops-lab). Role: ${var.role}"
  tags        = sort(concat(["lab", var.role], var.extra_tags))

  on_boot         = true
  started         = true
  stop_on_destroy = true

  clone {
    vm_id = var.template_id
    full  = true
  }

  agent {
    enabled = true
    timeout = "5m"
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
    # No ballooning: k3s and the kubelet make eviction decisions from the memory
    # they were given, and a balloon driver reclaiming it underneath skews that.
    floating = 0
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
    model   = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ipv4_cidr
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_account {
      username = var.admin_user
      keys     = var.ssh_public_keys
    }
  }

  lifecycle {
    # The template can be rebuilt without forcing every VM to be recreated.
    ignore_changes = [clone]
  }
}
