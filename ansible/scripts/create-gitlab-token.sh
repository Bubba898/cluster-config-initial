#!/bin/bash
set -euo pipefail

GITLAB_URL="$1"
GITLAB_ROOT_PASSWORD="$2"
GITLAB_TOKEN_NAME="$3"

# First, get a session token by logging in
echo "Authenticating as root user..." >&2
SESSION_TOKEN=$(curl -sf "${GITLAB_URL}/oauth/token" \
  -d "grant_type=password" \
  -d "username=root" \
  -d "password=${GITLAB_ROOT_PASSWORD}" \
  | jq -r '.access_token' 2>/dev/null || echo "")

if [ -z "$SESSION_TOKEN" ]; then
  echo "Failed to authenticate with root credentials. Trying alternative method..." >&2
  
  # Alternative: Use personal access tokens API with basic auth
  # First check if a token already exists
  EXISTING_TOKEN=$(curl -sf -u "root:${GITLAB_ROOT_PASSWORD}" \
    "${GITLAB_URL}/api/v4/personal_access_tokens" \
    | jq -r ".[] | select(.name == \"${GITLAB_TOKEN_NAME}\") | .id" | head -1 || echo "")
  
  if [ -n "$EXISTING_TOKEN" ]; then
    echo "Token '${GITLAB_TOKEN_NAME}' already exists (ID: $EXISTING_TOKEN). Using existing token." >&2
    # Note: We can't retrieve the actual token value, only revoke/create new
    echo "Revoking old token and creating a new one..." >&2
    curl -sf -u "root:${GITLAB_ROOT_PASSWORD}" \
      -X DELETE "${GITLAB_URL}/api/v4/personal_access_tokens/$EXISTING_TOKEN" || true
  fi
  
  # Create new token using Rails console via kubectl exec
  echo "Creating access token via GitLab Rails console..." >&2
  EXPIRES_AT=$(date -u -v+1y +"%Y-%m-%d")
  TOKEN=$(kubectl exec -n gitlab -it $(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -- \
    gitlab-rails runner "
      user = User.find_by(username: 'root')
      token = user.personal_access_tokens.create(
        name: '${GITLAB_TOKEN_NAME}',
        scopes: ['api', 'write_repository', 'read_repository'],
        expires_at: '${EXPIRES_AT}'
      )
      puts token.token if token.persisted?
    " 2>/dev/null | tr -d '\r' | grep -E '^glpat-[a-zA-Z0-9._-]+$' | head -1)
  
  if [ -n "$TOKEN" ]; then
    echo "$TOKEN"
    exit 0
  else
    echo "Failed to create access token via Rails console" >&2
    exit 1
  fi
else
  # Use session token to create personal access token
  echo "Creating personal access token..." >&2
  
  # Get user ID
  USER_ID=$(curl -sf -H "Authorization: Bearer $SESSION_TOKEN" \
    "${GITLAB_URL}/api/v4/user" | jq -r '.id')
  
  # Check for existing token
  EXISTING_TOKEN_ID=$(curl -sf -H "Authorization: Bearer $SESSION_TOKEN" \
    "${GITLAB_URL}/api/v4/personal_access_tokens" \
    | jq -r ".[] | select(.name == \"${GITLAB_TOKEN_NAME}\") | .id" | head -1 || echo "")
  
  if [ -n "$EXISTING_TOKEN_ID" ]; then
    echo "Revoking existing token..." >&2
    curl -sf -H "Authorization: Bearer $SESSION_TOKEN" \
      -X DELETE "${GITLAB_URL}/api/v4/personal_access_tokens/$EXISTING_TOKEN_ID" || true
  fi
  
  # Create new token - GitLab API requires expires_at and scopes in specific format
  echo "Attempting to create token via API..." >&2
  EXPIRES_AT=$(date -u -v+1y +"%Y-%m-%d")  # Set expiration to 1 year from now
  
  RESPONSE=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $SESSION_TOKEN" \
    -X POST "${GITLAB_URL}/api/v4/user/personal_access_tokens" \
    -H "Content-Type: application/json" \
    --data-raw "{\"name\":\"${GITLAB_TOKEN_NAME}\",\"scopes\":[\"api\",\"write_repository\",\"read_repository\"],\"expires_at\":\"${EXPIRES_AT}\"}")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    TOKEN=$(echo "$BODY" | jq -r '.token')
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
      echo "$TOKEN"
      exit 0
    else
      echo "Failed to extract token from response: $BODY" >&2
      exit 1
    fi
  else
    echo "API request failed with HTTP $HTTP_CODE: $BODY" >&2
    echo "Falling back to Rails console method..." >&2
    
    # Fallback: Use Rails console via kubectl exec
    echo "Creating access token via GitLab Rails console..." >&2
    EXPIRES_AT=$(date -u -v+1y +"%Y-%m-%d")
    TOKEN=$(kubectl exec -n gitlab -it $(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -- \
      gitlab-rails runner "
        user = User.find_by(username: 'root')
        token = user.personal_access_tokens.create(
          name: '${GITLAB_TOKEN_NAME}',
          scopes: ['api', 'write_repository', 'read_repository'],
          expires_at: '${EXPIRES_AT}'
        )
        puts token.token if token.persisted?
      " 2>/dev/null | tr -d '\r' | grep -E '^glpat-[a-zA-Z0-9._-]+$' | head -1)
    
    if [ -n "$TOKEN" ]; then
      echo "$TOKEN"
      exit 0
    else
      echo "Failed to create access token via Rails console" >&2
      exit 1
    fi
  fi
fi


