# Vault Policy: Powernode Backend Service
# Used by Rails API server for credential management
#
# This policy grants full access to account credentials and
# the ability to generate short-lived tokens for containers.

# Read system secrets (JWT keys, encryption master key)
path "secret/data/powernode/system/*" {
  capabilities = ["read"]
}

# Full access to account credentials
path "secret/data/powernode/accounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Metadata access for account credentials
path "secret/metadata/powernode/accounts/*" {
  capabilities = ["read", "list", "delete"]
}

# Create short-lived container secrets
path "secret/data/powernode/containers/*" {
  capabilities = ["create", "read", "delete"]
}

# Generate child tokens for container execution
path "auth/token/create/container-execution" {
  capabilities = ["create", "update"]
}

# Revoke tokens (cleanup after container execution)
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

# Lookup token info
path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

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
