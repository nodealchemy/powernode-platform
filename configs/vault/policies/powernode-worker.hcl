# Vault Policy: Powernode Worker Service
# Used by Sidekiq workers for background job credential access
#
# This policy grants read-only access to credentials needed
# for background processing (email, webhooks, AI tasks, etc.)

# Read system secrets
path "secret/data/powernode/system/*" {
  capabilities = ["read"]
}

# Read account credentials (needed for AI executions, integrations)
path "secret/data/powernode/accounts/*/ai-providers/*" {
  capabilities = ["read"]
}

path "secret/data/powernode/accounts/*/mcp-servers/*" {
  capabilities = ["read"]
}

path "secret/data/powernode/accounts/*/chat-channels/*" {
  capabilities = ["read"]
}

path "secret/data/powernode/accounts/*/git-credentials/*" {
  capabilities = ["read"]
}

# No write access - workers should not modify credentials

# Self token operations
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Health check
path "sys/health" {
  capabilities = ["read"]
}
