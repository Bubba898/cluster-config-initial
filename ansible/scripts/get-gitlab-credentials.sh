#!/bin/bash
set -euo pipefail

# Helper script to retrieve GitLab root password (for manual login/verification)
# Note: The migrate-to-incluster-gitlab.yml playbook automatically handles
# credential retrieval and token creation, so this script is optional.

echo "======================================================================"
echo "GitLab Credentials Helper (Informational)"
echo "======================================================================"
echo ""
echo "NOTE: The migration playbook now automatically retrieves credentials"
echo "      and creates access tokens. This script is for manual reference only."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Get ingress IP from configmap
INGRESS_IP=$(kubectl get configmap cluster-params -n flux-system -o jsonpath='{.data.INGRESS_IP}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
    echo "Warning: Could not retrieve INGRESS_IP from cluster-params ConfigMap"
    echo "Using placeholder. Replace with your actual ingress IP."
    INGRESS_IP="<INGRESS_IP>"
fi

GITLAB_URL="http://gitlab.${INGRESS_IP}.sslip.io"

# Get root password
echo "1. GitLab Root Password"
echo "   ====================="
echo ""
ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -z "$ROOT_PASSWORD" ]; then
    echo "   ❌ Could not retrieve root password."
    echo "   Make sure GitLab is deployed and the secret exists."
    echo ""
    echo "   Try manually:"
    echo "   kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d"
else
    echo "   Username: root"
    echo "   Password: $ROOT_PASSWORD"
    echo ""
    echo "   ✓ Save this password for login!"
fi

echo ""
echo "2. Manual Login (Optional)"
echo "   ======================="
echo ""
echo "   To manually access GitLab UI:"
echo ""
echo "   URL: $GITLAB_URL"
echo "   Username: root"
echo "   Password: $ROOT_PASSWORD"
echo ""
echo "3. Run the migration playbook"
echo "   ============================"
echo ""
echo "   The migration is now fully automated!"
echo "   Just run:"
echo ""
echo "   ansible-playbook -i inventory.ini migrate-to-incluster-gitlab.yml"
echo ""
echo "   The playbook will:"
echo "   - Automatically retrieve the root password"
echo "   - Create an access token via GitLab Rails console"
echo "   - Create the GitLab project"
echo "   - Push the repository"
echo "   - Configure Flux to use in-cluster GitLab"
echo ""
echo "======================================================================"

