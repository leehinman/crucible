terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4"
    }
  }
}

variable "ssh_key"         { type = string }
variable "agent_count"     { type = number }
variable "cloud_init_file" { type = string }

resource "multipass_instance" "es" {
  name           = "es"
  cpus           = 2
  memory         = "4G"
  disk           = "10G"
  cloudinit_file = var.cloud_init_file
}

resource "multipass_instance" "kibana" {
  name           = "kibana"
  cpus           = 1
  memory         = "2G"
  disk           = "10G"
  cloudinit_file = var.cloud_init_file
}

resource "multipass_instance" "fleet" {
  name           = "fleet"
  cpus           = 1
  memory         = "1G"
  disk           = "10G"
  cloudinit_file = var.cloud_init_file
}

resource "multipass_instance" "agents" {
  count          = var.agent_count
  name           = "a${count.index}"
  cpus           = 1
  memory         = "1G"
  disk           = "10G"
  cloudinit_file = var.cloud_init_file
}

output "es_ip"     { value = multipass_instance.es.ipv4 }
output "kibana_ip" { value = multipass_instance.kibana.ipv4 }
output "fleet_ip"  { value = multipass_instance.fleet.ipv4 }
output "agent_ips" { value = multipass_instance.agents[*].ipv4 }
