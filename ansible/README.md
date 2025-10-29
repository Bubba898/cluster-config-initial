# Ansible k3s Bootstrap

This folder contains Ansible playbooks to bootstrap a k3s cluster with settings tailored to this repo (Istio instead of Traefik, Longhorn prerequisites, etc.).

## Files
- `inventory.ini`: Define your nodes and SSH users
- `group_vars/all.yml`: Role variables configuring k3s
- `bootstrap.yml`: Playbook with host preparation and the k3s role
- `remove-k3s.yml`: Playbook to remove k3s and clean residual data
- `reset.yml`: Playbook that removes and re-bootstraps the cluster (combines remove-k3s.yml and bootstrap.yml)
- `requirements.yml`: Ansible Galaxy dependencies

## Usage
1) Install role dependencies:
```bash
ansible-galaxy install -r requirements.yml
```

2) Update `inventory.ini` and `group_vars/all.yml` placeholders:
- MASTER_IP

3) Bootstrap the k3s cluster:
```bash
ansible-playbook -i inventory.ini bootstrap.yml
```

### Remove / uninstall the k3s cluster

Run the removal playbook against the same inventory:

```bash
ansible-playbook -i inventory.ini remove-k3s.yml
```

Optional: trigger a reboot after removal by setting a variable:

```bash
ansible-playbook -i inventory.ini remove-k3s.yml -e reboot_after_k3s_removal=true
```

### Reset the k3s cluster (remove and re-bootstrap)

Run the reset playbook to completely remove k3s and then re-bootstrap it:

```bash
ansible-playbook -i inventory.ini reset.yml
```

Optional: trigger a reboot after removal (before re-bootstrapping):

```bash
ansible-playbook -i inventory.ini reset.yml -e reboot_after_k3s_removal=true
```

Notes:
- The playbook disables swap, installs open-iscsi and nfs-common for Longhorn, and disables Traefik so Istio handles ingress.
- For multi-node, add workers to `[workers]` and re-run. To move to HA later, switch to embedded etcd in vars.
