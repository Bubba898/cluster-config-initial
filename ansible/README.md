# Ansible k3s Bootstrap

This folder contains Ansible playbooks to bootstrap a k3s cluster with settings tailored to this repo (Istio instead of Traefik, Longhorn prerequisites, etc.).

## Files
- `inventory.ini`: Define your nodes and SSH users
- `group_vars/all.yml`: Role variables configuring k3s
- `site.yml`: Playbook with host preparation and the k3s role
- `requirements.yml`: Ansible Galaxy dependencies

## Usage
1) Install role dependencies:
```bash
ansible-galaxy install -r requirements.yml
```

2) Update `inventory.ini` and `group_vars/all.yml` placeholders:
- MASTER_IP
- GITLAB_HOST
- REGISTRY_HOST

3) Run the playbook:
```bash
ansible-playbook -i inventory.ini site.yml
```

Notes:
- The playbook disables swap, installs open-iscsi and nfs-common for Longhorn, and disables Traefik so Istio handles ingress.
- For multi-node, add workers to `[workers]` and re-run. To move to HA later, switch to embedded etcd in vars.
