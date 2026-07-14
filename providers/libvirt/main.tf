terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
  }
}

variable "ssh_key"            { type = string }
variable "agent_count"        { type = number }
variable "cloud_init_content" { type = string }
variable "storage_pool" {
  type    = string
  default = "elastic-cluster"
}

locals {
  es_ip     = "192.168.100.10"
  kibana_ip = "192.168.100.11"
  fleet_ip  = "192.168.100.12"
  agent_ips = [for i in range(var.agent_count) : "192.168.100.${20 + i}"]

  ubuntu_image_url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# ── Storage pool ──────────────────────────────────────────────────────────────

resource "libvirt_pool" "cluster" {
  name = var.storage_pool
  type = "dir"
  path = "/var/lib/libvirt/images/${var.storage_pool}"
}

# ── Network ────────────────────────────────────────────────────────────────────

resource "libvirt_network" "cluster" {
  name      = "elastic-cluster"
  mode      = "nat"
  domain    = "cluster.local"
  addresses = ["192.168.100.0/24"]
  autostart = true
  dhcp { enabled = true }
}

# ── Base image volume ──────────────────────────────────────────────────────────

resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-24.04-noble-base.qcow2"
  pool   = libvirt_pool.cluster.name
  source = local.ubuntu_image_url
  format = "qcow2"
}

# ── Disk volumes (cloned from base) ───────────────────────────────────────────

resource "libvirt_volume" "es" {
  name           = "es.qcow2"
  pool           = libvirt_pool.cluster.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  size           = 10737418240  # 10 GiB
}

resource "libvirt_volume" "kibana" {
  name           = "kibana.qcow2"
  pool           = libvirt_pool.cluster.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  size           = 10737418240
}

resource "libvirt_volume" "fleet" {
  name           = "fleet.qcow2"
  pool           = libvirt_pool.cluster.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  size           = 10737418240
}

resource "libvirt_volume" "agents" {
  count          = var.agent_count
  name           = "a${count.index}.qcow2"
  pool           = libvirt_pool.cluster.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  size           = 10737418240
}

# ── Cloud-init disks (one per VM with static network config) ───────────────────

resource "libvirt_cloudinit_disk" "es" {
  name           = "es-init.iso"
  pool           = libvirt_pool.cluster.name
  user_data      = var.cloud_init_content
  network_config = templatefile("${path.module}/network-config.tftpl", { ip = local.es_ip })
}

resource "libvirt_cloudinit_disk" "kibana" {
  name           = "kibana-init.iso"
  pool           = libvirt_pool.cluster.name
  user_data      = var.cloud_init_content
  network_config = templatefile("${path.module}/network-config.tftpl", { ip = local.kibana_ip })
}

resource "libvirt_cloudinit_disk" "fleet" {
  name           = "fleet-init.iso"
  pool           = libvirt_pool.cluster.name
  user_data      = var.cloud_init_content
  network_config = templatefile("${path.module}/network-config.tftpl", { ip = local.fleet_ip })
}

resource "libvirt_cloudinit_disk" "agents" {
  count          = var.agent_count
  name           = "a${count.index}-init.iso"
  pool           = libvirt_pool.cluster.name
  user_data      = var.cloud_init_content
  network_config = templatefile("${path.module}/network-config.tftpl", { ip = local.agent_ips[count.index] })
}

# ── Domains ────────────────────────────────────────────────────────────────────

resource "libvirt_domain" "es" {
  name   = "es"
  vcpu   = 2
  memory = 4096  # MiB

  cloudinit = libvirt_cloudinit_disk.es.id

  disk { volume_id = libvirt_volume.es.id }

  network_interface {
    network_id     = libvirt_network.cluster.id
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

resource "libvirt_domain" "kibana" {
  name   = "kibana"
  vcpu   = 1
  memory = 2048

  cloudinit = libvirt_cloudinit_disk.kibana.id

  disk { volume_id = libvirt_volume.kibana.id }

  network_interface {
    network_id     = libvirt_network.cluster.id
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

resource "libvirt_domain" "fleet" {
  name   = "fleet"
  vcpu   = 1
  memory = 1024

  cloudinit = libvirt_cloudinit_disk.fleet.id

  disk { volume_id = libvirt_volume.fleet.id }

  network_interface {
    network_id     = libvirt_network.cluster.id
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

resource "libvirt_domain" "agents" {
  count  = var.agent_count
  name   = "a${count.index}"
  vcpu   = 1
  memory = 1024

  cloudinit = libvirt_cloudinit_disk.agents[count.index].id

  disk { volume_id = libvirt_volume.agents[count.index].id }

  network_interface {
    network_id     = libvirt_network.cluster.id
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

output "es_ip"     { value = local.es_ip }
output "kibana_ip" { value = local.kibana_ip }
output "fleet_ip"  { value = local.fleet_ip }
output "agent_ips" { value = local.agent_ips }
