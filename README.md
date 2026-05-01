# Crucible

Provisions an Elastic Stack lab environment (Elasticsearch, Kibana, Fleet
Server, and Elastic Agents) using OpenTofu and Ansible. Supports three
providers: Multipass (local VMs), AWS, and GCP.

## Prerequisites

### Required tools

| Tool                                                                   | Purpose                                         |
|------------------------------------------------------------------------|-------------------------------------------------|
| [OpenTofu](https://opentofu.org/docs/intro/install/)                   | Provision VMs                                   |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | Configure and install the Elastic Stack         |
| [OpenSSH](https://www.openssh.com/)                                    | SSH client and `ssh-keyscan` (used by OpenTofu) |

### Provider-specific tools

Install only what you need for your chosen provider:

| Provider    | Tool                                                                                                                  |
|-------------|-----------------------------------------------------------------------------------------------------------------------|
| `multipass` | [Multipass](https://multipass.run/install)                                                                            |
| `aws`       | [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured with credentials |
| `gcp`       | [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud auth application-default login`)               |

### Ansible collections

```
ansible-galaxy collection install -r requirements.yml
```

This installs:
- `community.crypto` — TLS certificate generation
- `ansible.posix` — kernel parameter configuration

### OpenTofu providers

Providers are installed automatically by `tofu init`. No manual action needed.

### SSH key

An SSH public key is required for VM access. The default path is
`~/.ssh/id_rsa_yubikey.pub`. To use a different key, update
`ssh_public_key_file` in `group_vars/all.yml`.

## Configuration

Edit `group_vars/all.yml` before running:

```yaml
provider: "multipass"        # choices: multipass, aws, gcp

ssh_public_key_file: "~/.ssh/id_rsa_yubikey.pub"

agent_count: 2               # number of Elastic Agent VMs to create

elastic_version: "9.3.2"

elastic_password: "changeme" # use ansible-vault to encrypt in production
```

For AWS, also set `aws.region` and optionally `aws.key_pair_name`. For GCP,
set `gcp.project`, `gcp.region`, and `gcp.zone`.

## Usage

### 1. Initialize OpenTofu

```
tofu init
```

### 2. Provision VMs

```
tofu apply
```

This creates the VMs, generates `cloud-init.yaml` and `inventory.ini`, and
populates `~/.ssh/known_hosts` with the VM host keys.

### 3. Run the Ansible playbook

```
ansible-playbook -i inventory.ini playbooks/initialize/site.yml
```

This installs and configures Elasticsearch, Kibana, Fleet Server, and Elastic
Agents, and wires them together via the Fleet API.

### Teardown

```
tofu destroy
```
