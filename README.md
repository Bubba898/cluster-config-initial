# Cluster GitOps: k3s + Flux + MetalLB + Longhorn + Istio + Observability + GitLab

This repository manages a k3s cluster via GitOps using Flux. It includes:
- MetalLB for bare-metal load balancing
- Longhorn for persistent storage
- Istio (base, istiod, gateway) with Kiali
- Observability: kube-prometheus-stack, Loki, Jaeger
- GitLab with in-cluster Runner and Container Registry

## Prerequisites
- Either: a k3s cluster already running
- Or: use the Ansible playbook in `ansible/` to bootstrap k3s (recommended)
    1) Edit placeholders:
        - `ansible/inventory.ini`: set `MASTER_IP`, SSH user
    2) Install the Ansible role and run:
        - ```bash
            cd ansible
            ansible-galaxy install -r requirements.yml
            ansible-playbook -i inventory.ini site.yml
        ```
- `kubectl` and `flux` CLI installed (if you bootstrap Flux manually)
- DNS domain ready (e.g., example.com) and ability to point records to your MetalLB IP(s)
- Chosen Layer2 IP range on your LAN for MetalLB (unused range)

Default ingress IP
- This repo is preconfigured to use a single MetalLB IP: `192.168.178.240`.
- The Istio ingress Service is pinned to the same IP.
- You can change this IP by updating both:
  - `infrastructure/metallb/metallb.yaml` → `IPAddressPool.spec.addresses`
  - `istio/istio.yaml` → `istio-ingressgateway.values.service.loadBalancerIP`

Single-source IP configuration
- The IP is centrally defined as `INGRESS_IP` via Flux `postBuild.substitute` in `clusters/home/flux-system/gotk-sync.yaml`.
- Manifests reference `${INGRESS_IP}` so you only set it once.
- To change the IP:
  1. Edit `clusters/home/flux-system/gotk-sync.yaml` and set `INGRESS_IP` to your new address
  2. Commit and let Flux reconcile (MetalLB pool, Istio Service, and GitLab hosts will update)

Access without a domain (sslip.io)
- To use the stack without owning a domain, the manifests are pre-set to sslip.io hostnames that resolve automatically to the ingress IP:
  - `YOUR_DOMAIN`: `${INGRESS_IP}.sslip.io`
  - `GITLAB_HOST`: `gitlab.${INGRESS_IP}.sslip.io`
  - `REGISTRY_HOST`: `registry.${INGRESS_IP}.sslip.io`
- These are already configured in `apps/gitlab/gitlab.yaml` (including the Istio `Gateway`/`VirtualService`).
- When you later have a real domain, update `apps/gitlab/gitlab.yaml` accordingly and (optionally) add TLS via cert-manager.

## Cluster Configuration
- `clusters/home/flux-system/gotk-sync.yaml`: set `spec.url` to YOUR_GIT_REPO_URL
Search and replace the following placeholders in this repository before bootstrapping:
- YOUR_GIT_REPO_URL: Git URL of this repo (e.g., `ssh://git@your.git/owner/cluster-config.git`)
- YOUR_DOMAIN: base domain (e.g., `example.com`)
- METALLB_L2_RANGE: IP range for MetalLB (default single IP: `192.168.178.240-192.168.178.240`)
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
