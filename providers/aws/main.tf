terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "ssh_key"         { type = string }
variable "agent_count"     { type = number }
variable "cloud_init_file" { type = string }
variable "key_pair_name" {
  type    = string
  default = ""
}

# AMI: Ubuntu 24.04 LTS in us-east-1 — update if switching regions
locals {
  ami_id = "ami-0c7217cdde317cfec"
}

resource "aws_security_group" "elastic_stack" {
  name = "elastic-stack-sg"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "All traffic within SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "es" {
  ami                    = local.ami_id
  instance_type          = "t3.large"   # 2 vCPU, 8GB
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  user_data              = file(var.cloud_init_file)
  vpc_security_group_ids = [aws_security_group.elastic_stack.id]
  tags                   = { Name = "es" }
}

resource "aws_instance" "kibana" {
  ami                    = local.ami_id
  instance_type          = "t3.medium"  # 2 vCPU, 4GB
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  user_data              = file(var.cloud_init_file)
  vpc_security_group_ids = [aws_security_group.elastic_stack.id]
  tags                   = { Name = "kibana" }
}

resource "aws_instance" "fleet" {
  ami                    = local.ami_id
  instance_type          = "t3.small"   # 2 vCPU, 2GB
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  user_data              = file(var.cloud_init_file)
  vpc_security_group_ids = [aws_security_group.elastic_stack.id]
  tags                   = { Name = "fleet" }
}

resource "aws_instance" "agents" {
  count                  = var.agent_count
  ami                    = local.ami_id
  instance_type          = "t3.small"
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  user_data              = file(var.cloud_init_file)
  vpc_security_group_ids = [aws_security_group.elastic_stack.id]
  tags                   = { Name = "a${count.index}" }
}

output "es_ip"     { value = aws_instance.es.public_ip }
output "kibana_ip" { value = aws_instance.kibana.public_ip }
output "fleet_ip"  { value = aws_instance.fleet.public_ip }
output "agent_ips" { value = aws_instance.agents[*].public_ip }
