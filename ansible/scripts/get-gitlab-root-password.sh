#!/usr/bin/env bash
# Retrieves the GitLab root password from the Kubernetes secret

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   GitLab Root Credentials                                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Error: kubectl is not installed or not in PATH${NC}" >&2
    exit 1
fi

# Check if the secret exists
if ! kubectl get secret gitlab-initial-root-password -n gitlab &> /dev/null; then
    echo -e "${YELLOW}Error: GitLab root password secret not found${NC}" >&2
    echo "Make sure GitLab is deployed and the secret is created." >&2
    exit 1
fi

# Get the INGRESS_IP from the cluster
INGRESS_IP=$(kubectl get configmap cluster-params -n flux-system -o jsonpath='{.data.INGRESS_IP}' 2>/dev/null || echo "UNKNOWN")

# Retrieve the password
ROOT_PASSWORD=$(kubectl get secret gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d)

echo -e "${GREEN}GitLab URL:${NC} https://gitlab.${INGRESS_IP}.sslip.io"
echo -e "${GREEN}Registry URL:${NC} https://registry.${INGRESS_IP}.sslip.io"
echo ""
echo -e "${GREEN}Username:${NC} root"
echo -e "${GREEN}Password:${NC} ${ROOT_PASSWORD}"
echo ""
echo -e "${YELLOW}Note: This password provides full administrative access to GitLab.${NC}"
echo ""

