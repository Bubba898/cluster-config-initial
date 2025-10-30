#!/bin/bash
set -euo pipefail

# Script to create a GitLab Runner via API and retrieve its authentication token
# This follows the new runner registration workflow introduced in GitLab 15.10

GITLAB_URL="${1:-}"
GITLAB_TOKEN="${2:-}"
RUNNER_DESCRIPTION="${3:-k3s-cluster-runner}"

if [ -z "$GITLAB_URL" ] || [ -z "$GITLAB_TOKEN" ]; then
    echo "Usage: $0 <gitlab_url> <gitlab_access_token> [runner_description]"
    echo "Example: $0 http://gitlab.example.com glpat-xxxxx my-runner"
    exit 1
fi

echo "======================================================================"
echo "GitLab Runner Token Generator (New Workflow)"
echo "======================================================================"
echo ""
echo "GitLab URL: $GITLAB_URL"
echo "Runner Description: $RUNNER_DESCRIPTION"
echo ""

# Check if runner with this description already exists
echo "Checking for existing runner..."
EXISTING_RUNNERS=$(curl -sf -X GET \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/runners?type=instance_type&status=online,offline,paused" \
    2>/dev/null || echo "[]")

# Try to find an existing runner with matching description
EXISTING_RUNNER_ID=$(echo "$EXISTING_RUNNERS" | jq -r --arg desc "$RUNNER_DESCRIPTION" \
    '.[] | select(.description == $desc) | .id' | head -1)

if [ -n "$EXISTING_RUNNER_ID" ] && [ "$EXISTING_RUNNER_ID" != "null" ]; then
    echo "⚠️  Found existing runner with ID: $EXISTING_RUNNER_ID"
    echo "Note: Cannot retrieve the authentication token for an existing runner."
    echo "The token is only shown once during creation."
    echo ""
    
    # Check if AUTO_DELETE environment variable is set (for automation)
    if [ "${AUTO_DELETE:-false}" == "true" ]; then
        echo "AUTO_DELETE is set, deleting existing runner..."
        curl -sf -X DELETE \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/runners/$EXISTING_RUNNER_ID" >/dev/null
        echo "✓ Existing runner deleted"
        echo ""
    else
        echo "Options:"
        echo "1. Delete the existing runner and create a new one"
        echo "2. Use the token from the initial creation (if you saved it)"
        echo ""
        echo "To auto-delete in scripts, set: AUTO_DELETE=true"
        echo ""
        read -p "Delete existing runner and create new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Deleting existing runner..."
            curl -sf -X DELETE \
                -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                "$GITLAB_URL/api/v4/runners/$EXISTING_RUNNER_ID" >/dev/null
            echo "✓ Existing runner deleted"
            echo ""
        else
            echo "Keeping existing runner. Exiting."
            exit 1
        fi
    fi
fi

# Create a new instance runner
echo "Creating new GitLab runner..."
RESPONSE=$(curl -sf -X POST \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"runner_type\": \"instance_type\",
        \"description\": \"$RUNNER_DESCRIPTION\",
        \"tag_list\": [\"kubernetes\", \"k3s\"],
        \"run_untagged\": true,
        \"locked\": false,
        \"access_level\": \"not_protected\",
        \"maintenance_note\": \"Auto-created by Ansible bootstrap\"
    }" \
    "$GITLAB_URL/api/v4/user/runners" 2>/dev/null)

# Check if creation was successful
if [ -z "$RESPONSE" ]; then
    echo "❌ Failed to create runner. API returned empty response."
    exit 1
fi

# Extract the runner token
RUNNER_TOKEN=$(echo "$RESPONSE" | jq -r '.token' 2>/dev/null)

if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" == "null" ]; then
    echo "❌ Failed to extract runner token from response."
    echo "Response: $RESPONSE"
    exit 1
fi

# Verify the token starts with glrt- (runner authentication token)
if [[ ! "$RUNNER_TOKEN" =~ ^glrt- ]]; then
    echo "⚠️  Warning: Token does not start with 'glrt-'. This may not be a valid runner authentication token."
fi

echo "✓ Successfully created GitLab runner!"
echo ""
echo "Runner Token: $RUNNER_TOKEN"
echo ""
echo "This token should be used in the GitLab Runner Helm chart configuration."
echo "======================================================================"

# Output just the token for use in scripts
echo "$RUNNER_TOKEN"

