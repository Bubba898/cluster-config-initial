# GitLab Deployment Guide

This guide walks you through deploying GitLab on your homelab Kubernetes cluster using Flux CD, with TLS managed by cert-manager and ingress via Istio.

## Prerequisites

Before deploying GitLab, ensure the following are installed and running:

- ✅ **K3s cluster** (installed via Ansible)
- ✅ **Flux CD** (GitOps controller)
- ✅ **cert-manager** (TLS certificate management)
- ✅ **Longhorn** (persistent storage)
- ✅ **MetalLB** (load balancer)
- ✅ **Istio** (ingress gateway)

All of these should already be set up if you've run the Ansible bootstrap.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet/LAN                          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Istio Gateway       │
              │  192.168.178.240     │
              │  (TLS Termination)   │
              └──────────┬───────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
   ┌─────────┐    ┌──────────┐    ┌─────────┐
   │ GitLab  │    │ Registry │    │  MinIO  │
   │ Service │    │ Service  │    │ Service │
   └─────────┘    └──────────┘    └─────────┘
        │                │                │
        └────────────────┴────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   PostgreSQL + Redis  │
              │   (Persistent Volumes)│
              └──────────────────────┘
```

## Deployment Steps

### Step 1: Create GitLab Secrets

Before deploying GitLab, you need to create the required Kubernetes secrets. The Ansible playbook handles this automatically:

```bash
cd ansible
ansible-playbook setup-gitlab-secrets.yml
```

This playbook will:
- Create the `gitlab` namespace
- Generate secure random passwords for:
  - GitLab root user
  - PostgreSQL database
  - Redis cache
- Store credentials in `.gitlab-credentials.txt` in the repo root

**Important**: Save the generated credentials securely! You'll need the root password to log in.

### Step 2: Verify Configuration

The GitLab Helm chart is configured in `apps/gitlab/gitlab.yaml` with:

**TLS Configuration:**
- Uses existing `homelab-ca-issuer` ClusterIssuer
- Certificates for gitlab, registry, and minio subdomains
- 90-day validity with auto-renewal

**Ingress Configuration:**
- Istio Gateway handles all ingress traffic
- Automatic HTTP to HTTPS redirect
- Wildcard TLS certificate

**Resource Allocation:**
- CPU: ~750m total requests
- Memory: ~5Gi total requests  
- Storage: ~73Gi (Longhorn)

**Access URLs:**
- GitLab Web: `https://gitlab.192.168.178.240.sslip.io`
- Container Registry: `https://registry.192.168.178.240.sslip.io`
- MinIO Console: `https://minio.192.168.178.240.sslip.io`
- Git SSH: Port 32022 (NodePort)

### Step 3: Deploy GitLab

If you're using GitOps with Flux (recommended):

```bash
# Commit and push the changes
git add apps/gitlab/gitlab.yaml
git commit -m "feat: add GitLab Helm chart with TLS"
git push

# Trigger Flux reconciliation
flux reconcile source git flux-system
flux reconcile kustomization apps
```

Or manually apply:

```bash
kubectl apply -f apps/gitlab/gitlab.yaml
```

### Step 4: Monitor Deployment

GitLab deployment takes 15-30 minutes. Monitor progress:

```bash
# Watch all pods in gitlab namespace
kubectl get pods -n gitlab -w

# Check HelmRelease status
flux get helmreleases -n gitlab

# View detailed HelmRelease status
kubectl describe helmrelease gitlab -n gitlab

# Check for any errors
kubectl get events -n gitlab --sort-by='.lastTimestamp' | tail -20
```

**Expected pods:**
- `gitlab-webservice-*` (1-2 replicas)
- `gitlab-sidekiq-*` (1-2 replicas)
- `gitlab-gitaly-*` (1 replica)
- `gitlab-gitlab-shell-*` (1-2 replicas)
- `gitlab-migrations-*` (job, completes)
- `gitlab-toolbox-*` (1 replica)
- `gitlab-postgresql-*` (1 replica)
- `gitlab-redis-master-*` (1 replica)
- `gitlab-minio-*` (1 replica)
- `gitlab-registry-*` (1-2 replicas)

### Step 5: Verify TLS Certificates

Check that cert-manager has issued certificates:

```bash
# Check certificate status
kubectl get certificates -n gitlab

# Should show:
# NAME                  READY   SECRET                       AGE
# gitlab-tls            True    gitlab-tls-secret           1m
# gitlab-registry-tls   True    gitlab-registry-tls-secret  1m
# gitlab-minio-tls      True    gitlab-minio-tls-secret     1m

# Check certificate details
kubectl describe certificate gitlab-tls -n gitlab
```

### Step 6: Verify Istio Routing

Check that Istio VirtualServices are configured:

```bash
# List VirtualServices
kubectl get virtualservices -n gitlab

# Should show:
# NAME              GATEWAYS                      HOSTS                                     AGE
# gitlab            ["istio-system/default-gateway"]   ["gitlab.192.168.178.240.sslip.io"]      1m
# gitlab-registry   ["istio-system/default-gateway"]   ["registry.192.168.178.240.sslip.io"]    1m
# gitlab-minio      ["istio-system/default-gateway"]   ["minio.192.168.178.240.sslip.io"]       1m

# Verify gateway configuration
kubectl get gateway -n istio-system default-gateway -o yaml
```

### Step 7: Access GitLab

Once all pods are running and healthy:

1. Open your browser and navigate to: `https://gitlab.192.168.178.240.sslip.io`

2. You may see a certificate warning (since it's a self-signed CA). Add the homelab CA certificate to your browser's trusted certificates, or accept the warning.

3. Log in with:
   - **Username**: `root`
   - **Password**: Retrieved from `.gitlab-credentials.txt` or run:
     ```bash
     cd ansible/scripts
     ./get-gitlab-root-password.sh
     ```

4. Complete the initial setup wizard (if prompted)

5. Create your first project or import existing repositories

## Post-Deployment Configuration

### Trust the Homelab CA Certificate

To avoid certificate warnings, add the homelab CA certificate to your browser:

```bash
# Export the CA certificate
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > homelab-ca.crt

# Then import homelab-ca.crt into your browser's trusted certificates
```

**For macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab-ca.crt
```

**For Linux:**
```bash
sudo cp homelab-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

**For Windows:**
Double-click `homelab-ca.crt` and install it to "Trusted Root Certification Authorities"

### Configure Docker to Trust Registry

To push/pull images from the GitLab registry:

```bash
# Add the CA certificate to Docker's trusted CAs
mkdir -p /etc/docker/certs.d/registry.192.168.178.240.sslip.io
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > /etc/docker/certs.d/registry.192.168.178.240.sslip.io/ca.crt

# Test registry access
docker login registry.192.168.178.240.sslip.io
# Username: root or your GitLab username
# Password: your GitLab password or access token
```

### Configure Git SSH Access

GitLab SSH is exposed on port 32022:

```bash
# Add to ~/.ssh/config
Host gitlab.192.168.178.240.sslip.io
    Hostname 192.168.178.240
    Port 32022
    User git

# Test SSH connection
ssh -T git@gitlab.192.168.178.240.sslip.io
```

### Enable GitLab Runner (Optional)

To enable CI/CD with GitLab Runner, see the separate runner setup guide or uncomment the runner configuration in `gitlab.yaml`:

```yaml
gitlab-runner:
  install: true
```

Then reconcile Flux or re-apply the configuration.

## Troubleshooting

### Pods Stuck in Pending

Check PVC status:
```bash
kubectl get pvc -n gitlab
kubectl describe pvc <pvc-name> -n gitlab
```

Verify Longhorn is healthy:
```bash
kubectl get pods -n longhorn-system
```

### Pods Crashing or CrashLoopBackOff

Check pod logs:
```bash
kubectl logs -n gitlab <pod-name> --previous
kubectl describe pod -n gitlab <pod-name>
```

Common issues:
- **Database migrations failing**: Check PostgreSQL pod logs
- **Secret not found**: Verify secrets were created in Step 1
- **Memory issues**: Increase resource limits or add more cluster resources

### HelmRelease Failed

Check Flux HelmRelease status:
```bash
flux get helmreleases -n gitlab
kubectl get helmrelease gitlab -n gitlab -o yaml
```

View Helm release logs:
```bash
kubectl logs -n flux-system deploy/helm-controller
```

Force reconciliation:
```bash
flux reconcile helmrelease gitlab -n gitlab
```

### Certificate Issues

Check cert-manager logs:
```bash
kubectl logs -n cert-manager deploy/cert-manager
```

Verify ClusterIssuer is ready:
```bash
kubectl get clusterissuer homelab-ca-issuer -o yaml
```

Manually trigger certificate renewal:
```bash
kubectl delete certificate gitlab-tls -n gitlab
# Certificate will be automatically recreated
```

### Cannot Access GitLab Web Interface

1. Verify Istio Gateway is running:
   ```bash
   kubectl get pods -n istio-system | grep ingressgateway
   ```

2. Check Gateway service has external IP:
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway
   # Should show EXTERNAL-IP: 192.168.178.240
   ```

3. Verify VirtualServices:
   ```bash
   kubectl get virtualservices -n gitlab -o yaml
   ```

4. Test internal service access:
   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
     curl -v http://gitlab-webservice-default.gitlab.svc.cluster.local:8181
   ```

5. Check Istio routing:
   ```bash
   istioctl analyze -n gitlab
   ```

### Registry Push/Pull Fails

1. Verify registry is running:
   ```bash
   kubectl get pods -n gitlab | grep registry
   kubectl logs -n gitlab <registry-pod-name>
   ```

2. Check storage configuration:
   ```bash
   kubectl exec -n gitlab <registry-pod-name> -- cat /etc/docker/registry/config.yml
   ```

3. Verify MinIO is accessible:
   ```bash
   kubectl get pods -n gitlab | grep minio
   ```

## Maintenance

### Backup

Important data locations:
- **Git repositories**: Gitaly PVC (`data-gitlab-gitaly-0`)
- **Database**: PostgreSQL PVC (`data-gitlab-postgresql-0`)
- **Object storage**: MinIO PVC (`gitlab-minio`)

Use the GitLab backup command:
```bash
# Create backup
kubectl exec -it -n gitlab $(kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -- backup-utility

# Backups are stored in the default bucket in MinIO
```

Or use Longhorn's snapshot feature:
```bash
# Take Longhorn snapshots of all GitLab PVCs
kubectl get pvc -n gitlab -o name | xargs -I {} kubectl annotate {} longhorn.io/snapshot-requested="true"
```

### Upgrade GitLab

To upgrade to a new GitLab version:

1. Check the [GitLab upgrade path](https://docs.gitlab.com/ee/update/#upgrade-paths)
2. Update the version in `gitlab.yaml`:
   ```yaml
   chart:
     spec:
       version: "8.5.0"  # Specify exact version
   ```
3. Commit and push, or manually reconcile:
   ```bash
   flux reconcile helmrelease gitlab -n gitlab
   ```
4. Monitor the upgrade:
   ```bash
   kubectl get pods -n gitlab -w
   kubectl logs -n gitlab -l app=migrations -f
   ```

**Note**: Major version upgrades may require intermediate versions. Always backup before upgrading!

### Scale Resources

To adjust resources:

1. Edit `apps/gitlab/gitlab.yaml`
2. Modify `minReplicas`, `maxReplicas`, or resource requests/limits
3. Apply changes via Git or kubectl
4. Pods will be automatically recreated

### Uninstall GitLab

**Warning**: This will delete all GitLab data!

```bash
# Delete HelmRelease
kubectl delete helmrelease gitlab -n gitlab

# Wait for resources to clean up
kubectl get all -n gitlab

# Delete PVCs (this deletes all data!)
kubectl delete pvc -n gitlab --all

# Delete namespace
kubectl delete namespace gitlab

# Delete certificates
kubectl delete certificate -n gitlab --all
```

## Resources

- [GitLab Helm Chart Documentation](https://docs.gitlab.com/charts/)
- [GitLab TLS Configuration](https://docs.gitlab.com/charts/installation/tls/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Istio Gateway Documentation](https://istio.io/latest/docs/reference/config/networking/gateway/)
- [Flux CD Documentation](https://fluxcd.io/flux/)

## Support

For issues specific to this deployment:
1. Check the troubleshooting section above
2. Review Kubernetes events and pod logs
3. Check the GitLab Helm chart documentation
4. Consult the #homelab or #kubernetes communities

For GitLab-specific questions:
- [GitLab Community Forum](https://forum.gitlab.com/)
- [GitLab Documentation](https://docs.gitlab.com/)

