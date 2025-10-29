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
    1) Edit `ansible/inventory.ini`:
        - set `ansible_host` to the IP of your host machine (where k3s is gonna run)
        - set `ansible_user` to the user on your host machine
        - (optionall) `ansible_ssh_private_key_file` to a ssh key file with access to the machine (you can use ssh-copy-id from step 2a)
    2) Set up SSH access to your host machine
        a) My way on mac os
            1) ssh-copy-id $ansible_user@$ansible_host
            2) ssh-add --apple-use-keychain ~/.ssh/$ssh_key_file_path
            3) Configure ~/.ssh/config so SSH/Ansible pick it up automatically:
                ```
Host $ansible_host
User $ansible_user
IdentityFile $ssh_key_file_path
AddKeysToAgent yes
UseKeychain yes```
    3) Install the Ansible role and run:
        - ```bash
            cd ansible
            ansible-galaxy install -r requirements.yml
            ansible-playbook -i inventory.ini site.yml
        ```
        - Use ```bash ansible-playbook -i inventory.ini site.yml --ask-become-pass``` if sudo access is required (This is the case when following 2)
- `kubectl` and `flux` CLI installed (if you bootstrap Flux manually)
- DNS domain ready (e.g., example.com) and ability to point records to your MetalLB IP(s)
- Chosen Layer2 IP range on your LAN for MetalLB (unused range)

Default ingress IP
- This repo is preconfigured to use a single MetalLB IP: `192.168.178.240`.
- The Istio ingress Service is pinned to the same IP.
- You centrally configure this IP once (see next section); manifests reference it automatically.

Single-source IP configuration
- The source of truth is `ansible/group_vars/all.yml` → `ingress_ip`.
- The Ansible play (`ansible/site.yml`) publishes this into a ConfigMap `flux-system/cluster-params` with key `INGRESS_IP`.
- Flux `Kustomization` objects use `postBuild.substituteFrom` to read from that ConfigMap, so `${INGRESS_IP}` is expanded across manifests.
- To change the IP:
  1. Edit `ansible/group_vars/all.yml` and set `ingress_ip: "NEW_IP"`
  2. Run the Ansible playbook again so it updates the `cluster-params` ConfigMap
  3. Flux will reconcile and apply the new value (MetalLB pool, Istio Service, GitLab, etc.)

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

### Temporary fork for bootstrapping (YOUR_GIT_REPO_URL)
To get Flux running before the in-cluster GitLab is available, use a temporary remote (your fork) as `YOUR_GIT_REPO_URL`, then switch to the in-cluster GitLab later.

1) Create a temporary repo (fork or new project) on any reachable Git provider (e.g., GitHub/GitLab.com):
   - Fork this repository to your own account, or create an empty repo and push this code there.
   - Copy its Git URL (SSH recommended), e.g. `git@github.com:your-user/cluster-config.git`.

2) Point Flux to your temporary repo:
   - Edit `cansible/group_vars/all.yml` and set:
     - `bootstrap_git_repo_url` → your fork URL

3) Bootstrap using the temporary repo (see "Bootstrap Flux" below). Flux will reconcile from this remote and deploy the stack, including GitLab.

4) After GitLab is up in-cluster, switch Flux to the in-cluster GitLab repository:
   - Create a new project in your in-cluster GitLab (e.g., at `https://GITLAB_HOST/`), e.g. `infrastructure/cluster-config`.
   - Add the in-cluster GitLab as a new remote and push all branches/tags:
     ```bash
     git remote add incluster git@GITLAB_HOST:group/cluster-config.git
     git push incluster --all
     git push incluster --tags
     ```
   - Update `clusters/home/flux-system/gotk-sync.yaml` to set `spec.url` to the in-cluster GitLab URL (SSH or HTTPS).
   - Apply the updated sync manifest so Flux starts reconciling from the new remote:
     ```bash
     kubectl apply -f clusters/home/flux-system/gotk-sync.yaml
     ```
   - (Optional) Remove the temporary remote from your local repo.

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
