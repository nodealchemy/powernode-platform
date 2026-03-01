# Vault Policy: Container Execution
# Used by short-lived container tokens during AI agent execution
#
# This policy is highly restricted and scoped to specific account
# using token metadata. Containers can only read secrets for their
# assigned account and execution context.

# Read only specific account secrets (bound by token metadata)
# The {{identity.entity.metadata.account_id}} template restricts access
# to only the account associated with the container token
path "secret/data/powernode/accounts/{{identity.entity.metadata.account_id}}/ai-providers/*" {
  capabilities = ["read"]
}

path "secret/data/powernode/accounts/{{identity.entity.metadata.account_id}}/mcp-servers/*" {
  capabilities = ["read"]
}

# Read container-specific secrets (temporary, TTL-bounded)
path "secret/data/powernode/containers/{{identity.entity.metadata.execution_id}}/*" {
  capabilities = ["read"]
}

# Explicitly deny access to system secrets
path "secret/data/powernode/system/*" {
  capabilities = ["deny"]
}

# Deny access to other accounts
path "secret/data/powernode/accounts/*" {
  capabilities = ["deny"]
}

# Allow specific paths after general deny
path "secret/data/powernode/accounts/{{identity.entity.metadata.account_id}}/*" {
  capabilities = ["read"]
}

# Deny all token operations except lookup-self
path "auth/token/*" {
  capabilities = ["deny"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Health check only
path "sys/health" {
  capabilities = ["read"]
}

# No access to sys endpoints
path "sys/*" {
  capabilities = ["deny"]
}

path "sys/health" {
  capabilities = ["read"]
}
