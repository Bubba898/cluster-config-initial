# GitLab Installation

This directory contains the Flux HelmRelease configuration for GitLab CE (Community Edition).

## Overview

GitLab is installed using the official GitLab Helm chart and configured for a homelab environment with:
- GitLab web interface
- Container Registry
- Built-in PostgreSQL and Redis
- MinIO for object storage
- Integration with existing cert-manager and Istio

## Configuration

### Components Installed

- **GitLab Web Service**: Main GitLab application
- **Sidekiq**: Background job processing
- **Gitaly**: Git repository storage (50Gi persistent volume)
- **GitLab Shell**: Git SSH access on port 32022
- **Container Registry**: Docker image registry
- **PostgreSQL**: Database (8Gi persistent volume)
- **Redis**: Caching and job queue (5Gi persistent volume)
- **MinIO**: Object storage for artifacts, LFS, uploads (10Gi persistent volume)

### Resource Requirements

The configuration is optimized for a homelab with minimal resource requests:
- **Total CPU requests**: ~750m
- **Total memory requests**: ~5Gi
- **Total storage**: ~73Gi (using Longhorn storage class)

### Access URLs

After deployment, GitLab will be available at:
- **Web Interface**: `https://gitlab.${INGRESS_IP}.sslip.io`
- **Container Registry**: `https://registry.${INGRESS_IP}.sslip.io`

## Initial Setup

### 1. Secrets are Automatically Generated ✅

**Good news!** GitLab secrets are automatically generated during the Ansible bootstrap process with secure random passwords. The `setup-gitlab-secrets.yml` playbook:

- Generates cryptographically secure random passwords
- Creates Kubernetes secrets for:
  - GitLab root user password
  - PostgreSQL database password
  - Redis cache password
- Saves credentials to `.gitlab-credentials.txt` in the repo root

**To retrieve the root password later:**

```bash
cd ansible/scripts
./get-gitlab-root-password.sh
```

**Manual secret creation (if needed):**

If you're not using the Ansible bootstrap, you can manually run:

```bash
# Run the secrets setup playbook
ansible-playbook ansible/setup-gitlab-secrets.yml
```

Or create secrets manually:

```bash
# Create namespace first
kubectl create namespace gitlab

# Create initial root password
kubectl create secret generic gitlab-initial-root-password \
  --from-literal=password='YourSecurePassword' \
  -n gitlab

# Create PostgreSQL password
kubectl create secret generic gitlab-postgresql-password \
  --from-literal=password='YourSecurePostgresPassword' \
  -n gitlab

# Create Redis password
kubectl create secret generic gitlab-redis-password \
  --from-literal=password='YourSecureRedisPassword' \
  -n gitlab
```

### 2. Deploy GitLab

After committing and pushing the changes, Flux will automatically deploy GitLab. You can also manually reconcile:

```bash
# Trigger Flux reconciliation
flux reconcile source git flux-system
flux reconcile kustomization apps
```

### 3. Monitor Deployment

GitLab deployment can take 15-30 minutes. Monitor progress with:

```bash
# Watch pods
kubectl get pods -n gitlab -w

# Check HelmRelease status
flux get helmreleases -n gitlab

# View detailed status
kubectl describe helmrelease gitlab -n gitlab
```

### 4. Access GitLab

Once all pods are running:

1. Navigate to `https://gitlab.${INGRESS_IP}.sslip.io`
2. Login with:
   - Username: `root`
   - Password: The password you set in `gitlab-initial-root-password` secret

## Configuration Options

### Enabling GitLab Runner

To enable the GitLab Runner for CI/CD:

```yaml
gitlab:
  gitlab-runner:
    install: true
    runners:
      config: |
        [[runners]]
          executor = "kubernetes"
          [runners.kubernetes]
            namespace = "gitlab"
            image = "ubuntu:22.04"
```

### Scaling

To increase replicas for better performance:

```yaml
gitlab:
  webservice:
    minReplicas: 2
    maxReplicas: 3
  sidekiq:
    minReplicas: 2
    maxReplicas: 3
```

### External PostgreSQL/Redis

If you prefer to use external databases, set:

```yaml
postgresql:
  install: false
redis:
  install: false

global:
  psql:
    host: postgresql.example.com
    port: 5432
    database: gitlabhq_production
    username: gitlab
  redis:
    host: redis.example.com
    port: 6379
```

## Troubleshooting

### Pods Not Starting

Check events and logs:

```bash
# Check events
kubectl get events -n gitlab --sort-by='.lastTimestamp'

# Check specific pod logs
kubectl logs -n gitlab <pod-name>

# Check all pod statuses
kubectl get pods -n gitlab -o wide
```

### Storage Issues

Verify Longhorn is working:

```bash
# Check PVCs
kubectl get pvc -n gitlab

# Check Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system
```

### Helm Release Failed

Check HelmRelease status and conditions:

```bash
flux get helmreleases -n gitlab
kubectl describe helmrelease gitlab -n gitlab
```

Force reconciliation:

```bash
flux reconcile helmrelease gitlab -n gitlab
```

### Access Issues

Verify Istio VirtualServices:

```bash
kubectl get virtualservice -n gitlab
kubectl describe virtualservice gitlab -n gitlab
kubectl describe virtualservice gitlab-registry -n gitlab
```

Check Gateway configuration:

```bash
kubectl get gateway -n istio-system default-gateway -o yaml
```

## Maintenance

### Backup

Important data to backup:
- **Gitaly PV**: Git repositories (`gitaly-*` pods)
- **PostgreSQL PV**: Database (`gitlab-postgresql-*` pods)
- **MinIO PV**: Object storage (artifacts, uploads)

### Upgrade

To upgrade GitLab, update the version in the HelmRelease:

```yaml
chart:
  spec:
    version: "7.x.x"  # Specify version instead of "*"
```

Or keep using `"*"` for automatic updates (not recommended for production).

### Uninstall

To remove GitLab:

```bash
# Delete HelmRelease (will trigger uninstall)
kubectl delete helmrelease gitlab -n gitlab

# Wait for resources to be cleaned up
kubectl get all -n gitlab

# Optionally delete PVCs (this will delete all data!)
kubectl delete pvc -n gitlab --all

# Delete namespace
kubectl delete namespace gitlab
```

## Resources

- [GitLab Helm Chart Documentation](https://docs.gitlab.com/charts/)
- [GitLab Chart Configuration](https://docs.gitlab.com/charts/charts/globals.html)
- [GitLab Architecture](https://docs.gitlab.com/ee/development/architecture.html)

