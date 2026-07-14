terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
  }
}

# ── Read group_vars ────────────────────────────────────────────────────────────

locals {
  group_vars          = yamldecode(file("${path.module}/group_vars/all.yml"))
  provider_name       = local.group_vars.provider
  ssh_public_key_file = pathexpand(local.group_vars.ssh_public_key_file)
  agent_count         = local.group_vars.agent_count
  ssh_public_key      = trimspace(file(local.ssh_public_key_file))
  aws_cfg             = try(local.group_vars.aws, {})
  gcp_cfg             = try(local.group_vars.gcp, {})
  libvirt_cfg         = try(local.group_vars.libvirt, {})
}

# ── Provider configurations ────────────────────────────────────────────────────

provider "multipass" {}

provider "aws" {
  region = try(local.aws_cfg.region, "us-east-1")

  # When not using AWS, supply dummy credentials and skip all validation so
  # the provider doesn't error out during plan/apply for other providers.
  access_key                  = local.provider_name != "aws" ? "not-in-use" : null
  secret_key                  = local.provider_name != "aws" ? "not-in-use" : null
  skip_credentials_validation = local.provider_name != "aws"
  skip_requesting_account_id  = local.provider_name != "aws"
  skip_metadata_api_check     = local.provider_name != "aws"
}

provider "google" {
  project     = local.gcp_cfg.project != "" ? local.gcp_cfg.project : null
  region      = try(local.gcp_cfg.region, "us-central1")
  zone        = try(local.gcp_cfg.zone, "us-central1-a")
  # Supply a dummy credential to prevent ADC lookup when GCP is not in use.
  credentials = local.provider_name != "gcp" ? jsonencode({
    type          = "authorized_user"
    client_id     = "not-in-use"
    client_secret = "not-in-use"
    refresh_token = "not-in-use"
  }) : null
}

provider "libvirt" {
  uri = try(local.libvirt_cfg.uri, "qemu:///system")
}

# ── Generate cloud-init.yaml ───────────────────────────────────────────────────

resource "local_file" "cloud_init" {
  filename = "${path.module}/cloud-init.yaml"
  content  = templatefile("${path.module}/templates/cloud-init.tftpl", {
    ssh_public_key = local.ssh_public_key
  })
}

# ── Provider modules (exactly one active via count) ───────────────────────────

module "multipass" {
  count           = local.provider_name == "multipass" ? 1 : 0
  source          = "./providers/multipass"
  ssh_key         = local.ssh_public_key
  agent_count     = local.agent_count
  cloud_init_file = local_file.cloud_init.filename
  providers       = { multipass = multipass }
}

module "aws" {
  count           = local.provider_name == "aws" ? 1 : 0
  source          = "./providers/aws"
  ssh_key         = local.ssh_public_key
  agent_count     = local.agent_count
  cloud_init_file = local_file.cloud_init.filename
  key_pair_name   = try(local.aws_cfg.key_pair_name, "")
  providers       = { aws = aws }
}

module "gcp" {
  count           = local.provider_name == "gcp" ? 1 : 0
  source          = "./providers/gcp"
  ssh_key         = local.ssh_public_key
  agent_count     = local.agent_count
  cloud_init_file = local_file.cloud_init.filename
  gcp_zone        = try(local.gcp_cfg.zone, "us-central1-a")
  providers       = { google = google }
}

module "libvirt" {
  count              = local.provider_name == "libvirt" ? 1 : 0
  source             = "./providers/libvirt"
  ssh_key            = local.ssh_public_key
  agent_count        = local.agent_count
  cloud_init_content = local_file.cloud_init.content
  storage_pool       = try(local.libvirt_cfg.storage_pool, "default")
  providers          = { libvirt = libvirt }
}

# ── Unify IPs from whichever module is active ─────────────────────────────────

locals {
  es_ip = coalesce(
    try(module.multipass[0].es_ip, null),
    try(module.aws[0].es_ip,       null),
    try(module.gcp[0].es_ip,       null),
    try(module.libvirt[0].es_ip,   null),
  )
  kibana_ip = coalesce(
    try(module.multipass[0].kibana_ip, null),
    try(module.aws[0].kibana_ip,       null),
    try(module.gcp[0].kibana_ip,       null),
    try(module.libvirt[0].kibana_ip,   null),
  )
  fleet_ip = coalesce(
    try(module.multipass[0].fleet_ip, null),
    try(module.aws[0].fleet_ip,       null),
    try(module.gcp[0].fleet_ip,       null),
    try(module.libvirt[0].fleet_ip,   null),
  )
  agent_ips = coalesce(
    try(module.multipass[0].agent_ips, null),
    try(module.aws[0].agent_ips,       null),
    try(module.gcp[0].agent_ips,       null),
    try(module.libvirt[0].agent_ips,   null),
  )
}

# ── Generate inventory.ini ─────────────────────────────────────────────────────

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"
  content  = templatefile("${path.module}/templates/inventory.tftpl", {
    es_ip     = local.es_ip
    kibana_ip = local.kibana_ip
    fleet_ip  = local.fleet_ip
    agent_ips = local.agent_ips
  })
}

# ── Populate known_hosts ───────────────────────────────────────────────────────

resource "null_resource" "known_hosts" {
  depends_on = [module.multipass, module.aws, module.gcp, module.libvirt]

  triggers = {
    es_ip     = local.es_ip
    kibana_ip = local.kibana_ip
    fleet_ip  = local.fleet_ip
    agent_ips = join(",", local.agent_ips)
  }

  provisioner "local-exec" {
    command = <<-EOT
      for h in ${join(" ", concat([local.es_ip, local.kibana_ip, local.fleet_ip], local.agent_ips))}; do
        until ssh-keyscan -T 5 -H "$h" >> ~/.ssh/known_hosts 2>/dev/null; do
          echo "Waiting for SSH on $h..."; sleep 5
        done
      done
    EOT
  }
}
