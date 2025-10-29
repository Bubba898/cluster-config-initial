# Cluster GitOps: k3s + Flux + MetalLB + Longhorn + Istio + Observability + GitLab

This repository manages a k3s cluster via GitOps using Flux. It includes:
- MetalLB for bare-metal load balancing
- Longhorn for persistent storage
- Istio (base, istiod, gateway) with Kiali
- Observability: kube-prometheus-stack, Loki, Jaeger
- GitLab with in-cluster Runner and Container Registry

## Prerequisites
- A k3s cluster (single node is fine to start)
- `kubectl` and `flux` CLI installed
- DNS domain ready (e.g., example.com) and ability to point records to your MetalLB IP(s)
- Chosen Layer2 IP range on your LAN for MetalLB (unused range)

## Configure placeholders
Search and replace the following placeholders in this repository before bootstrapping:
- YOUR_GIT_REPO_URL: Git URL of this repo (e.g., `ssh://git@your.git/owner/cluster-config.git`)
- YOUR_DOMAIN: base domain (e.g., `example.com`)
- METALLB_L2_RANGE: IP range for MetalLB (e.g., `192.168.1.240-192.168.1.250`)
- GITLAB_HOST: GitLab FQDN (e.g., `gitlab.example.com`)
- REGISTRY_HOST: Registry FQDN (e.g., `registry.example.com`)

## Bootstrap Flux
1) Install Flux components (CRDs and controllers):

```bash
flux install
```

2) Commit and push this repository to your Git server, then apply the sync manifests to point Flux at this repo:

```bash
kubectl apply -f clusters/home/flux-system/gotk-sync.yaml
```

Flux will reconcile the following layers (order):
1. infrastructure (MetalLB, Longhorn)
2. istio (base, control-plane, gateway, Kiali)
3. observability (Prometheus/Grafana, Loki, Jaeger)
4. apps (GitLab + Runner)

## Notes
- For TLS certificates, you can add cert-manager later and reference it from Istio Gateways. This repo uses HTTP by default for simplicity.
- GitLab resources requirements are significant; ensure the node has sufficient CPU/RAM/disk. Consider disabling unused subcharts in values if needed.
- Longhorn will create a default StorageClass and set it as default; adjust if you have other storage.

## Cleanup
To remove all resources reconciled by Flux, delete the `Kustomization` objects in `clusters/home/flux-system/gotk-sync.yaml` (in reverse order) and uninstall Flux with `flux uninstall`.
