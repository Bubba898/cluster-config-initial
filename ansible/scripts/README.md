# Ansible Helper Scripts

This directory contains helper shell scripts for managing GitLab, GitLab Runner, and Headlamp in the k3s cluster.

## GitLab Credential Management

### `get-gitlab-credentials.sh`
Retrieves the GitLab root password from the Kubernetes cluster.

**Usage:**
```bash
./get-gitlab-credentials.sh
```

**What it does:**
- Fetches the root password from `gitlab-gitlab-initial-root-password` secret
- Displays the GitLab URL and login credentials
- Useful for manual GitLab UI access

---

### `create-gitlab-token.sh`
Creates a Personal Access Token (PAT) via GitLab API or retrieves an existing one.

**Usage:**
```bash
./create-gitlab-token.sh <gitlab_url> <root_password> <token_name>
```

**Example:**
```bash
./create-gitlab-token.sh "https://gitlab.192.168.1.100.sslip.io" "mypassword" "automation-token"
```

**What it does:**
- Authenticates with GitLab using root credentials
- Creates a PAT with `api`, `write_repository`, and `read_repository` scopes
- Returns existing token if one with the same name exists
- Used automatically by Ansible playbooks

---

## Headlamp Dashboard Access

### `get-headlamp-token.sh`
Retrieves the authentication token for accessing the Headlamp Kubernetes dashboard.

**Usage:**
```bash
./get-headlamp-token.sh
```

**What it does:**
- Fetches the user authentication token from `headlamp-user-token` secret in `kube-system`
- Displays the token for logging into Headlamp UI
- This token has **cluster-admin** privileges

**When to use:**
- First time accessing Headlamp UI
- Need to generate a new login token
- Sharing access with team members

---

## GitLab Runner Token Management

### `create-runner-token.sh` ✅ Recommended
Creates a GitLab Runner using the **new authentication token workflow** (GitLab 15.10+).

**Usage:**
```bash
./create-runner-token.sh <gitlab_url> <access_token> [runner_description]
```

**Example:**
```bash
./create-runner-token.sh "https://gitlab.192.168.1.100.sslip.io" "glpat-xxxxx" "k3s-runner"
```

**Environment Variables:**
- `AUTO_DELETE=true` - Automatically delete and recreate existing runners (for automation)

**What it does:**
- Creates an instance runner via GitLab API
- Returns a runner authentication token (format: `glrt-*`)
- Configures runner with tags: `kubernetes`, `k3s`
- Handles existing runners (interactive or automatic deletion)
- Used automatically by Ansible during bootstrap

**Why use this:**
- ✅ Uses the modern GitLab runner workflow
- ✅ More secure and flexible
- ✅ Future-proof (registration tokens will be removed in GitLab 20.0)

---

### `update-runner-token.sh`
Standalone script to update the runner token in an existing cluster.

**Usage:**
```bash
./update-runner-token.sh
```

**What it does:**
1. Retrieves GitLab credentials from the cluster
2. Creates a new GitLab access token
3. Creates a new runner authentication token
4. Patches the GitLab Runner HelmRelease with the new token
5. Triggers Flux reconciliation

**When to use:**
- Need to rotate runner tokens
- Runner token was compromised
- Runner stopped working and needs re-registration

---

### `get-runner-token.sh` ⚠️ DEPRECATED
Retrieves the runner **registration token** using the deprecated workflow.

**⚠️ WARNING:** This uses the deprecated runner registration token workflow. Runner registration tokens are scheduled for removal in **GitLab 20.0**.

**Usage:**
```bash
./get-runner-token.sh
```

**What it does:**
- Retrieves the instance-wide registration token from GitLab
- Uses GitLab Rails console via the toolbox pod
- Outputs the deprecated `glrtr-*` format token

**Migration:**
Use `create-runner-token.sh` instead, which creates runners with authentication tokens (`glrt-*` format).

---

## Quick Reference

| Script | Workflow | Status | Output Format |
|--------|----------|--------|---------------|
| `create-runner-token.sh` | Authentication Token | ✅ Recommended | `glrt-*` |
| `get-runner-token.sh` | Registration Token | ⚠️ Deprecated | `glrtr-*` |
| `update-runner-token.sh` | Authentication Token | ✅ Recommended | Updates cluster |
| `create-gitlab-token.sh` | PAT Creation | ✅ Active | `glpat-*` |
| `get-gitlab-credentials.sh` | Credential Retrieval | ✅ Active | Password |
| `get-headlamp-token.sh` | Token Retrieval | ✅ Active | JWT Token |

---

## Automation Integration

These scripts are called automatically by Ansible playbooks:

- **`migrate-to-incluster-gitlab.yml`:**
  - Calls `create-gitlab-token.sh` to create API access token
  - Calls `create-runner-token.sh` to create runner and get authentication token
  - Patches GitLab Runner HelmRelease with the token

- **Manual Updates:**
  - Run `update-runner-token.sh` from the `ansible/` directory when you need to regenerate tokens

---

## Additional Resources

- [GitLab Runner Registration Documentation](https://docs.gitlab.com/runner/register/)
- [New Runner Creation Workflow](https://docs.gitlab.com/ci/runners/new_creation_workflow/)
- [Runner Authentication Token Migration](https://docs.gitlab.com/ee/ci/runners/new_creation_workflow.html)



