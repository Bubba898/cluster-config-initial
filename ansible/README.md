# Ansible k3s Bootstrap

This folder contains Ansible playbooks to bootstrap a k3s cluster with settings tailored to this repo (Istio instead of Traefik, Longhorn prerequisites, etc.).

## Files Structure

### Configuration Files
- `inventory.ini`: Define your nodes and SSH users
- `group_vars/all.yml`: Role variables configuring k3s
- `requirements.yml`: Ansible Galaxy dependencies

### Scripts
- `scripts/`: Helper shell scripts for GitLab, runner, and Headlamp management
  - `create-gitlab-token.sh`: Create a Personal Access Token via GitLab API
  - `create-runner-token.sh`: Create a runner authentication token (new workflow)
  - `get-gitlab-credentials.sh`: Retrieve GitLab root password from cluster
  - `get-runner-token.sh`: Get runner registration token (⚠️ DEPRECATED)
  - `update-runner-token.sh`: Update runner token in an existing cluster
  - `get-headlamp-token.sh`: Retrieve Headlamp authentication token

### Bootstrap Playbooks
- `bootstrap.yml`: Main orchestration playbook that runs the complete setup
- `prepare-nodes.yml`: System preparation (packages, swap disable, iscsid)
- `install-k3s.yml`: K3s cluster installation using xanmanning.k3s role
- `setup-kubeconfig.yml`: Fetch and merge kubeconfig to local machine
- `setup-flux.yml`: Install and configure Flux GitOps
- `setup-headlamp-auth.yml`: Configure Headlamp dashboard authentication

### Maintenance Playbooks
- `remove-k3s.yml`: Playbook to remove k3s and clean residual data
- `reset.yml`: Playbook that removes and re-bootstraps the cluster (combines remove-k3s.yml and bootstrap.yml)
- `migrate-to-incluster-gitlab.yml`: Automate migration from external Git repo to in-cluster GitLab

### Cluster Management Playbooks
- `start-cluster.yml`: Start the k3s cluster services on all nodes
- `stop-cluster.yml`: Stop the k3s cluster services on all nodes
- `restart-cluster.yml`: Restart the k3s cluster services (useful after configuration changes)

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
- Install Flux and deploy all applications (including GitLab and Headlamp)
- **Automatically migrate Flux to use in-cluster GitLab** (once GitLab is ready)
- **Configure Headlamp dashboard authentication** and display the access token

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

**To access GitLab UI**: Run `./scripts/get-gitlab-credentials.sh` to get the root password for manual login.

### GitLab Runner Token Management

The GitLab Runner is automatically configured during the bootstrap process using the new runner authentication token workflow (introduced in GitLab 15.10).

**Automatic Setup (during bootstrap)**:
The `migrate-to-incluster-gitlab.yml` playbook automatically:
- Creates a new GitLab Runner via the GitLab API
- Retrieves the runner authentication token (format: `glrt-*`)
- Updates the GitLab Runner HelmRelease with the token
- The runner is immediately available for CI/CD pipelines

**Manual Token Update** (if needed):
If you need to regenerate the runner token after initial setup:

```bash
./scripts/update-runner-token.sh
```

This script will:
1. Retrieve GitLab credentials from the cluster
2. Create a new runner authentication token via GitLab API
3. Update the GitLab Runner HelmRelease
4. Trigger reconciliation to apply changes

**Scripts Available** (in `scripts/` directory):
- `create-runner-token.sh` - Create a new runner authentication token (new workflow, recommended)
- `update-runner-token.sh` - Update runner token in an existing cluster
- `get-runner-token.sh` - Get runner registration token (⚠️ DEPRECATED, will be removed in GitLab 20.0)
- `create-gitlab-token.sh` - Create GitLab Personal Access Token via API
- `get-gitlab-credentials.sh` - Retrieve GitLab credentials from cluster

**Note**: Runner registration tokens (format: `glrtr-*`) are deprecated. The new workflow uses runner authentication tokens (format: `glrt-*`) which are more secure and provide better control over runner configuration.

### Headlamp Dashboard Authentication

The Headlamp Kubernetes dashboard is automatically configured during the bootstrap process with a user authentication token that has cluster-admin privileges.

**Automatic Setup (during bootstrap)**:
The `setup-headlamp-auth.yml` playbook automatically:
- Creates a ServiceAccount (`headlamp-user`) with cluster-admin permissions
- Generates a long-lived authentication token
- Displays the token during bootstrap
- Saves the token to `.headlamp-token.txt` (git-ignored for security)

**Retrieve Token** (anytime after setup):
```bash
./scripts/get-headlamp-token.sh
```

Or retrieve it from the saved file:
```bash
cat .headlamp-token.txt
```

**Access Headlamp**:
The dashboard is available at `https://headlamp.<INGRESS_IP>.sslip.io`

When prompted for authentication, paste the token displayed during bootstrap or retrieved via the script above.

**Security Note**: 
- The token has **full cluster-admin privileges**
- It is saved to `.headlamp-token.txt` which is automatically added to `.gitignore`
- Store and share the token securely
- The token does not expire

### Cluster Management Operations

Use these playbooks to manage your running cluster:

**Start the cluster** (after a shutdown or node reboot):
```bash
ansible-playbook -i inventory.ini start-cluster.yml
```

**Stop the cluster** (graceful shutdown):
```bash
ansible-playbook -i inventory.ini stop-cluster.yml
```

**Restart the cluster** (after configuration changes or to resolve issues):
```bash
ansible-playbook -i inventory.ini restart-cluster.yml
```

These playbooks handle master and worker nodes in the correct order to ensure cluster stability. The restart playbook also displays cluster status and pod health after completion.

Notes:
- The playbook disables swap, installs open-iscsi and nfs-common for Longhorn, and disables Traefik so Istio handles ingress.
- For multi-node, add workers to `[workers]` and re-run. To move to HA later, switch to embedded etcd in vars.
