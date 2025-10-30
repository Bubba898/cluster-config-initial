#!/usr/bin/env bash
set -euo pipefail

# Get the Headlamp user token for authentication
echo "Retrieving Headlamp user token..."
echo ""

TOKEN=$(kubectl get secret headlamp-user-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

echo "Copy this token to authenticate to Headlamp:"
echo ""
echo "$TOKEN"
echo ""
echo "This token has cluster-admin privileges."

