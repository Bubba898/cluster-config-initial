# GitLab Quick Start

For busy admins who just want to get GitLab running quickly.

## Prerequisites

✅ K3s cluster with Flux, cert-manager, Longhorn, MetalLB, and Istio installed

## Deploy in 3 Steps

### 1. Create Secrets

```bash
cd ansible
ansible-playbook setup-gitlab-secrets.yml
```

Save the displayed root password!

### 2. Deploy GitLab

```bash
# Commit and push (if using GitOps)
git add apps/gitlab/
git commit -m "feat: add GitLab with TLS"
git push

# Trigger Flux reconciliation
flux reconcile source git flux-system
flux reconcile kustomization apps
```

### 3. Wait and Monitor

```bash
# Watch deployment (takes 15-30 minutes)
kubectl get pods -n gitlab -w

# Check when all pods are running
kubectl get pods -n gitlab
```

## Access GitLab

Open: `https://gitlab.192.168.178.240.sslip.io`

Login:
- **Username**: `root`
- **Password**: From `.gitlab-credentials.txt` or run:
  ```bash
  cd ansible/scripts && ./get-gitlab-root-password.sh
  ```

## Accept Self-Signed Certificate

Your browser will warn about the certificate. Either:
- Click "Advanced" → "Accept Risk and Continue"
- Or trust the CA certificate permanently (see DEPLOYMENT.md)

## Quick Commands

```bash
# Check deployment status
flux get helmreleases -n gitlab

# View logs
kubectl logs -n gitlab -l app=webservice

# Get root password
kubectl get secret gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d

# Access URLs
echo "GitLab:   https://gitlab.192.168.178.240.sslip.io"
echo "Registry: https://registry.192.168.178.240.sslip.io"
echo "MinIO:    https://minio.192.168.178.240.sslip.io"
```

## Troubleshooting

**Pods not starting?**
```bash
kubectl describe pod <pod-name> -n gitlab
kubectl logs <pod-name> -n gitlab
```

**HelmRelease failed?**
```bash
kubectl describe helmrelease gitlab -n gitlab
flux reconcile helmrelease gitlab -n gitlab
```

**Can't access web interface?**
```bash
# Check if gateway is working
kubectl get svc -n istio-system istio-ingressgateway

# Should show EXTERNAL-IP: 192.168.178.240
```

For detailed troubleshooting, see [DEPLOYMENT.md](./DEPLOYMENT.md).

## Next Steps

1. Create your first project
2. Set up CI/CD with GitLab Runner (optional)
3. Configure container registry for Docker
4. Set up SSH access for Git operations

See [DEPLOYMENT.md](./DEPLOYMENT.md) for complete post-deployment configuration.

