#!/bin/bash
set -euo pipefail

# Script to retrieve GitLab runner registration token
# ⚠️  WARNING: This uses the DEPRECATED runner registration token workflow
# Runner registration tokens are scheduled for removal in GitLab 20.0
# 
# For new deployments, use create-runner-token.sh instead which creates
# runner authentication tokens via the GitLab API (new workflow)

echo "======================================================================"
echo "GitLab Runner Registration Token Retriever (DEPRECATED)"
echo "======================================================================"
echo ""
echo "⚠️  WARNING: Runner registration tokens are deprecated!"
echo "    This workflow will be removed in GitLab 20.0"
echo ""
echo "    For the new workflow, use: create-runner-token.sh"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Get the GitLab toolbox pod
TOOLBOX_POD=$(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$TOOLBOX_POD" ]; then
    echo "Error: Could not find GitLab toolbox pod"
    echo "Make sure GitLab is deployed and running"
    exit 1
fi

echo "Using GitLab toolbox pod: $TOOLBOX_POD"
echo ""
echo "Retrieving runner registration token..."
echo ""

# Get the runner registration token using GitLab Rails console
RUNNER_TOKEN=$(kubectl exec -n gitlab "$TOOLBOX_POD" -- \
    gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null || echo "")

if [ -z "$RUNNER_TOKEN" ]; then
    echo "❌ Could not retrieve runner registration token"
    echo ""
    echo "You can manually get it from:"
    echo "1. Login to GitLab UI at: https://gitlab.192.168.178.240.sslip.io"
    echo "2. Go to: Admin Area > CI/CD > Runners"
    echo "3. Copy the registration token"
    exit 1
fi

echo "✓ Successfully retrieved runner registration token!"
echo ""
echo "Runner Registration Token: $RUNNER_TOKEN"
echo ""
echo "Updating the runner-registration secret..."
echo ""

# Update the secret
kubectl patch secret runner-registration -n gitlab \
    --type='json' \
    -p="[{'op': 'replace', 'path': '/data/registrationToken', 'value': '$(echo -n "$RUNNER_TOKEN" | base64)'}]"

echo "✓ Secret updated successfully!"
echo ""
echo "Now restart the runner pod to apply the new token:"
echo "  kubectl delete pod -n gitlab -l app=gitlab-runner"
echo ""
echo "======================================================================"

