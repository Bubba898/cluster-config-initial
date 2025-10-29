# Ansible k3s Bootstrap

This folder contains Ansible playbooks to bootstrap a k3s cluster with settings tailored to this repo (Istio instead of Traefik, Longhorn prerequisites, etc.).

## Files
- `inventory.ini`: Define your nodes and SSH users
- `group_vars/all.yml`: Role variables configuring k3s
- `requirements.yml`: Ansible Galaxy dependencies

### Bootstrap Playbooks
- `bootstrap.yml`: Main orchestration playbook that runs the complete setup
- `prepare-nodes.yml`: System preparation (packages, swap disable, iscsid)
- `install-k3s.yml`: K3s cluster installation using xanmanning.k3s role
- `setup-kubeconfig.yml`: Fetch and merge kubeconfig to local machine
- `setup-flux.yml`: Install and configure Flux GitOps

### Maintenance Playbooks
- `remove-k3s.yml`: Playbook to remove k3s and clean residual data
- `reset.yml`: Playbook that removes and re-bootstraps the cluster (combines remove-k3s.yml and bootstrap.yml)
- `migrate-to-incluster-gitlab.yml`: Automate migration from external Git repo to in-cluster GitLab

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

This will:
- Prepare nodes and install k3s
- Set up kubeconfig on your local machine
- Install Flux and deploy all applications (including GitLab)
- **Automatically migrate Flux to use in-cluster GitLab** (once GitLab is ready)

### Run individual bootstrap steps

For more granular control, you can run individual playbooks:

```bash
# Prepare nodes only
ansible-playbook -i inventory.ini prepare-nodes.yml

# Install k3s only
ansible-playbook -i inventory.ini install-k3s.yml

# Setup kubeconfig only
ansible-playbook -i inventory.ini setup-kubeconfig.yml

# Setup Flux only
ansible-playbook -i inventory.ini setup-flux.yml
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

**Note**: The reset playbook automatically updates your local kubeconfig as part of the bootstrap process. When the cluster is recreated, new TLS certificates are generated, so the kubeconfig must be refreshed. This is handled automatically by the `bootstrap.yml` playbook which includes `setup-kubeconfig.yml`.

If you encounter certificate errors when running `kubectl` commands after a reset (e.g., "certificate signed by unknown authority"), you can manually update your kubeconfig:

```bash
ansible-playbook -i inventory.ini setup-kubeconfig.yml
```

### Migrate to In-Cluster GitLab

**NOTE**: The migration to in-cluster GitLab now happens **automatically** as part of the `bootstrap.yml` playbook! After GitLab is deployed, the bootstrap process automatically migrates Flux to sync from the in-cluster GitLab.

If you need to run the migration manually (e.g., to re-run it or if you skipped it during bootstrap):

```bash
ansible-playbook -i inventory.ini migrate-to-incluster-gitlab.yml
```

The migration playbook automatically:
- Waits for GitLab to be fully deployed and ready
- Retrieves the GitLab root password from Kubernetes secrets
- Creates an access token via GitLab Rails console (no manual token creation needed!)
- Creates a GitLab group and project (default: `infrastructure/cluster-config`)
- Pushes the repository to in-cluster GitLab
- Updates `group_vars/all.yml` to use the in-cluster repository
- Reconfigures Flux to sync from in-cluster GitLab
- Verifies the migration was successful

After migration, Flux will automatically sync from the in-cluster GitLab. You can push changes directly to the in-cluster repository:
```bash
git push incluster main
```

**To access GitLab UI**: Run `./get-gitlab-credentials.sh` to get the root password for manual login.

Notes:
- The playbook disables swap, installs open-iscsi and nfs-common for Longhorn, and disables Traefik so Istio handles ingress.
- For multi-node, add workers to `[workers]` and re-run. To move to HA later, switch to embedded etcd in vars.
