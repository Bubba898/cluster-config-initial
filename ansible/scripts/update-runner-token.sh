#!/bin/bash
set -euo pipefail

# Helper script to update GitLab Runner authentication token in an existing cluster
# This script:
# 1. Gets GitLab credentials from the cluster
# 2. Creates a new runner authentication token via GitLab API
# 3. Updates the GitLab Runner HelmRelease with the new token
# 4. Triggers reconciliation

echo "======================================================================"
echo "GitLab Runner Token Updater"
echo "======================================================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is not installed or not in PATH"
    exit 1
fi

# Get ingress IP from configmap
echo "📋 Getting cluster configuration..."
INGRESS_IP=$(kubectl get configmap cluster-params -n flux-system -o jsonpath='{.data.INGRESS_IP}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
    echo "❌ Could not get INGRESS_IP from cluster-params configmap"
    exit 1
fi

echo "   Ingress IP: $INGRESS_IP"

# Set GitLab URLs
GITLAB_URL="https://gitlab.${INGRESS_IP}.sslip.io"
GITLAB_INTERNAL_URL="http://gitlab-webservice-default.gitlab.svc.cluster.local:8181"

echo "   GitLab URL: $GITLAB_URL"
echo ""

# Get GitLab root password
echo "🔑 Getting GitLab credentials..."
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [ -z "$GITLAB_PASSWORD" ]; then
    echo "❌ Could not get GitLab root password from secret"
    exit 1
fi

echo "   ✓ Retrieved GitLab root password"
echo ""

# Create or get access token
echo "🎫 Creating GitLab access token..."
# Script is in ansible/scripts/, so SCRIPT_DIR will be ansible/scripts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/create-gitlab-token.sh" ]; then
    echo "❌ create-gitlab-token.sh not found in $SCRIPT_DIR"
    exit 1
fi

GITLAB_TOKEN=$("$SCRIPT_DIR/create-gitlab-token.sh" "$GITLAB_URL" "$GITLAB_PASSWORD" "runner-token-update" 2>/dev/null | tail -1)

if [ -z "$GITLAB_TOKEN" ]; then
    echo "❌ Failed to create/retrieve GitLab access token"
    exit 1
fi

echo "   ✓ Access token retrieved"
echo ""

# Create runner token
echo "🏃 Creating new GitLab Runner authentication token..."

if [ ! -f "$SCRIPT_DIR/create-runner-token.sh" ]; then
    echo "❌ create-runner-token.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Set AUTO_DELETE to automatically recreate runner if it exists
export AUTO_DELETE=true

RUNNER_TOKEN=$("$SCRIPT_DIR/create-runner-token.sh" "$GITLAB_URL" "$GITLAB_TOKEN" "k3s-cluster-runner" 2>/dev/null | tail -1)

if [ -z "$RUNNER_TOKEN" ]; then
    echo "❌ Failed to create runner authentication token"
    exit 1
fi

# Verify the token format
if [[ ! "$RUNNER_TOKEN" =~ ^glrt- ]]; then
    echo "❌ Invalid runner token format (expected to start with 'glrt-')"
    exit 1
fi

echo "   ✓ Runner token created: $RUNNER_TOKEN"
echo ""

# Update the HelmRelease
echo "📝 Updating GitLab Runner HelmRelease..."

kubectl patch helmrelease gitlab-runner -n gitlab --type=merge -p "{\"spec\":{\"values\":{\"runnerToken\":\"$RUNNER_TOKEN\"}}}"

if [ $? -eq 0 ]; then
    echo "   ✓ HelmRelease patched successfully"
else
    echo "❌ Failed to patch HelmRelease"
    exit 1
fi
echo ""

# Trigger reconciliation
echo "🔄 Triggering Flux reconciliation..."
if command -v flux &> /dev/null; then
    flux reconcile helmrelease gitlab-runner -n gitlab --timeout=5m
    echo "   ✓ Reconciliation triggered"
else
    echo "   ℹ️  flux CLI not found, skipping automatic reconciliation"
    echo "   Manual reconciliation: flux reconcile helmrelease gitlab-runner -n gitlab"
fi
echo ""

# Check runner pod status
echo "🔍 Checking GitLab Runner pod status..."
kubectl get pods -n gitlab -l app=gitlab-runner
echo ""

echo "======================================================================"
echo "✅ Runner token update complete!"
echo "======================================================================"
echo ""
echo "New runner token: $RUNNER_TOKEN"
echo ""
echo "The GitLab Runner pod should restart automatically."
echo "Monitor status with: kubectl get pods -n gitlab -l app=gitlab-runner -w"
echo ""
echo "======================================================================"

