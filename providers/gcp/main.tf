terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "ssh_key"         { type = string }
variable "agent_count"     { type = number }
variable "cloud_init_file" { type = string }
variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

resource "google_compute_firewall" "elastic_stack_ssh" {
  name    = "elastic-stack-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["elastic-stack"]
}

resource "google_compute_firewall" "elastic_stack_internal" {
  name    = "elastic-stack-allow-internal"
  network = "default"

  allow { protocol = "all" }
  source_tags = ["elastic-stack"]
  target_tags = ["elastic-stack"]
}

resource "google_compute_instance" "es" {
  name         = "es"
  machine_type = "n2-standard-2"  # 2 vCPU, 8GB
  zone         = var.gcp_zone
  tags         = ["elastic-stack"]

  boot_disk {
    initialize_params { image = "ubuntu-os-cloud/ubuntu-2404-lts" }
  }
  network_interface {
    network = "default"
    access_config {}  # ephemeral public IP
  }
  metadata = { "user-data" = file(var.cloud_init_file) }
}

resource "google_compute_instance" "kibana" {
  name         = "kibana"
  machine_type = "n2-standard-2"  # 2 vCPU, 8GB
  zone         = var.gcp_zone
  tags         = ["elastic-stack"]

  boot_disk {
    initialize_params { image = "ubuntu-os-cloud/ubuntu-2404-lts" }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = { "user-data" = file(var.cloud_init_file) }
}

resource "google_compute_instance" "fleet" {
  name         = "fleet"
  machine_type = "n1-standard-1"  # 1 vCPU, 3.75GB
  zone         = var.gcp_zone
  tags         = ["elastic-stack"]

  boot_disk {
    initialize_params { image = "ubuntu-os-cloud/ubuntu-2404-lts" }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = { "user-data" = file(var.cloud_init_file) }
}

resource "google_compute_instance" "agents" {
  count        = var.agent_count
  name         = "a${count.index}"
  machine_type = "n1-standard-1"
  zone         = var.gcp_zone
  tags         = ["elastic-stack"]

  boot_disk {
    initialize_params { image = "ubuntu-os-cloud/ubuntu-2404-lts" }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = { "user-data" = file(var.cloud_init_file) }
}

output "es_ip"     { value = google_compute_instance.es.network_interface[0].access_config[0].nat_ip }
output "kibana_ip" { value = google_compute_instance.kibana.network_interface[0].access_config[0].nat_ip }
output "fleet_ip"  { value = google_compute_instance.fleet.network_interface[0].access_config[0].nat_ip }
output "agent_ips" { value = [for i in google_compute_instance.agents : i.network_interface[0].access_config[0].nat_ip] }
