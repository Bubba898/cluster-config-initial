# Cluster GitOps: k3s + Flux + MetalLB + Longhorn + Istio + Observability + GitLab

This repository manages a k3s cluster via GitOps using Flux. It includes:
- MetalLB for bare-metal load balancing
- Longhorn for persistent storage
- Istio (base, istiod, gateway) with Kiali
- Observability: kube-prometheus-stack, Loki, Jaeger
- GitLab with in-cluster Runner and Container Registry

## Quick Start

The entire cluster can be bootstrapped using the Ansible playbooks in the `ansible/` directory. The playbooks handle:
- k3s installation and configuration
- Flux GitOps setup

### Prerequisites

- One or more Linux servers (tested with Ubuntu)
- SSH access to the server(s)
- Ansible installed on your local machine
- `kubectl` CLI installed locally (optional, for manual cluster access)

## Cluster Configuration

All cluster configuration is centralized in `ansible/group_vars/all.yml`. Key settings:

- `ingress_ip`: The MetalLB IP address for the Istio ingress gateway (default: `192.168.178.240`)
- `bootstrap_git_repo_url`: Git repository URL for Flux to sync from

The Ansible playbook creates a ConfigMap (`flux-system/cluster-params`) with these values, which Flux uses to substitute variables across all manifests using `${INGRESS_IP}` and other placeholders.

## Setup Instructions

### 1. Configure Cluster Parameters

Edit `ansible/group_vars/all.yml`:
- Set `ingress_ip` to an available IP on your LAN for MetalLB

### 2. Configure Inventory

Edit `ansible/inventory.ini` to define your cluster nodes:
- Set the master node IP address and SSH user
- (Optional) Add worker nodes to the `[workers]` group
- (Optional) Set `ansible_ssh_private_key_file` if using a specific SSH key

Example SSH setup on macOS:
```bash
# Copy SSH key to remote host
ssh-copy-id user@host-ip

# Add key to macOS keychain
ssh-add --apple-use-keychain ~/.ssh/id_rsa

# Configure ~/.ssh/config
Host 192.168.178.xxx
  User youruser
  IdentityFile ~/.ssh/id_rsa
  AddKeysToAgent yes
  UseKeychain yes
```

### 3. Bootstrap the Cluster

```bash
cd ansible

# Install Ansible Galaxy dependencies
ansible-galaxy install -r requirements.yml

# Run the complete bootstrap
ansible-playbook -i inventory.ini bootstrap.yml
```
If sudo password is required, add:
```bash
ansible-playbook -i inventory.ini bootstrap.yml --ask-become-pass
```

The bootstrap playbook will:
1. Prepare nodes (disable swap, install packages, configure storage)
2. Install k3s cluster (with Traefik disabled for Istio)
3. Fetch and merge kubeconfig to your local machine
4. Install Flux and configure GitOps sync
5. **Automatically migrate to in-cluster GitLab** (after GitLab is deployed)

Flux will automatically reconcile all components in the following order:
1. **infrastructure**: MetalLB, Longhorn, MetalLB IP pool configuration
2. **istio**: Istio base, control plane, gateway, Kiali
3. **observability**: Prometheus/Grafana stack, Loki, Jaeger
4. **apps**: GitLab with Runner and Container Registry

After GitLab is deployed, the bootstrap process automatically migrates Flux to sync from the in-cluster GitLab instead of the external repository.

### 4. Verify Deployment

```bash
# Check Flux reconciliation status
kubectl get kustomizations -n flux-system

# Check all pods are running
kubectl get pods -A

# Get the ingress IP
kubectl get svc -n istio-system istio-ingressgateway
```

## Access Without a Domain (sslip.io)

The manifests use [sslip.io](https://sslip.io) for automatic DNS resolution without requiring a real domain:

- GitLab: `http://gitlab.${INGRESS_IP}.sslip.io`
- Container Registry: `http://registry.${INGRESS_IP}.sslip.io`
- Headlamp (K8s dashboard): `http://headlamp.${INGRESS_IP}.sslip.io`

For example, with `ingress_ip: 192.168.178.240`:
- GitLab: `http://gitlab.192.168.178.240.sslip.io`

When you have a real domain, update the relevant manifests in `apps/` and configure DNS records to point to your `ingress_ip`.

## Changing Configuration

To update cluster configuration after initial bootstrap:

1. Edit `ansible/group_vars/all.yml` (e.g., change `ingress_ip`)
2. Re-run the setup-flux playbook to update the ConfigMap:
   ```bash
   ansible-playbook -i inventory.ini setup-flux.yml
   ```
3. Flux will automatically reconcile and apply changes across all manifests

## In-Cluster GitLab Migration

The bootstrap process **automatically migrates** Flux to use the in-cluster GitLab after it's deployed. This happens as the final step of `bootstrap.yml`.

The migration:
- ✅ Retrieves GitLab root password from Kubernetes secrets
- ✅ Creates an access token via GitLab Rails console
- ✅ Creates a GitLab project (`infrastructure/cluster-config`)
- ✅ Pushes your repository to in-cluster GitLab
- ✅ Updates Flux to sync from the in-cluster repository
- ✅ Verifies the migration succeeded

After bootstrap completes, you can push changes directly to the in-cluster GitLab:
```bash
git push incluster main
```

Flux will automatically sync changes from the in-cluster GitLab to your cluster.

### Manual Migration

If you need to run the migration separately (e.g., if you skipped it during bootstrap or need to re-run it):

```bash
cd ansible
ansible-playbook -i inventory.ini migrate-to-incluster-gitlab.yml
```

**To access GitLab UI**: Run `./get-gitlab-credentials.sh` to get the root password.

See `ansible/README.md` for more details.

## Individual Playbook Steps

For more granular control, you can run individual playbooks (see `ansible/README.md` for details):


## Maintenance

### Remove k3s Cluster

To completely remove k3s and clean up all resources:

```bash
cd ansible
ansible-playbook -i inventory.ini remove-k3s.yml

# Optionally reboot after removal
ansible-playbook -i inventory.ini remove-k3s.yml -e reboot_after_k3s_removal=true
```

### Reset and Re-bootstrap

To remove k3s and immediately re-bootstrap from scratch:

```bash
cd ansible
ansible-playbook -i inventory.ini reset.yml

# With optional reboot between removal and bootstrap
ansible-playbook -i inventory.ini reset.yml -e reboot_after_k3s_removal=true
```

## Notes

- **TLS/HTTPS**: This repo uses HTTP by default for simplicity. To add TLS, install cert-manager and configure certificates in the Istio Gateway definitions.
- **GitLab Resources**: GitLab requires significant CPU/RAM/disk. Ensure your node(s) have adequate resources (recommend 8GB+ RAM, 4+ CPU cores).
- **Storage**: Longhorn creates a default StorageClass. If you have existing storage solutions, you may want to adjust the default StorageClass settings.
- **Scaling**: To add worker nodes, add them to the `[workers]` group in `inventory.ini` and re-run `ansible-playbook -i inventory.ini install-k3s.yml`.
- **High Availability**: For HA, configure `k3s_etcd_datastore: true` in `ansible/group_vars/all.yml` and set up multiple master nodes.

## Troubleshooting

### Check Ansible Logs
```bash
# Run with verbose output
ansible-playbook -i inventory.ini bootstrap.yml -v
```


## References

- [k3s Documentation](https://docs.k3s.io/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [Istio Documentation](https://istio.io/latest/docs/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [MetalLB Documentation](https://metallb.universe.tf/)
