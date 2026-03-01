# frozen_string_literal: true

# HashiCorp Vault Configuration
#
# This initializer configures the Vault client for secret management.
# Vault is used for:
# - AI provider credentials (API keys)
# - DevOps integration credentials (Git tokens)
# - MCP server OAuth tokens
# - Chat channel credentials
# - Short-lived container execution tokens
#
# Required environment variables:
# - VAULT_ADDR: Vault server address (default: https://vault.powernode.internal:8200)
# - VAULT_ROLE_ID: AppRole role ID for authentication
# - VAULT_SECRET_ID: AppRole secret ID for authentication
#
# Optional:
# - VAULT_SKIP_VERIFY: Skip TLS verification (default: false, only for dev)
# - VAULT_CA_CERT: Path to CA certificate for TLS verification

Rails.application.config.after_initialize do
  # Skip Vault initialization in test environment
  next if Rails.env.test?

  # Check if Vault configuration is present
  vault_configured = ENV["VAULT_ADDR"].present? &&
                     ENV["VAULT_ROLE_ID"].present? &&
                     ENV["VAULT_SECRET_ID"].present?

  if vault_configured
    begin
      # Verify Vault connectivity
      vault = Security::VaultClient.new

      if vault.healthy?
        Rails.logger.info "Vault connection established successfully"

        status = vault.status
        Rails.logger.info "Vault version: #{status[:version]}"
        Rails.logger.info "Vault cluster: #{status[:cluster_name]}"
      else
        Rails.logger.warn "Vault is configured but not healthy - sealed: #{vault.sealed?}"
      end
    rescue Security::VaultClient::VaultError => e
      Rails.logger.error "Vault initialization failed: #{e.message}"
      Rails.logger.warn "Credentials will fall back to database encryption"
    end
  else
    if Rails.env.production?
      Rails.logger.warn "Vault not configured in production - credentials stored in database"
    else
      Rails.logger.info "Vault not configured - using database encryption for credentials"
    end
  end
end

# Configure Vault health check for monitoring
Rails.application.config.to_prepare do
  # Register Vault health check if using a health check library
  if defined?(HealthCheck)
    HealthCheck.add_custom_check("vault") do
      if ENV["VAULT_ADDR"].present?
        Security::VaultClient.healthy? ? "" : "Vault unhealthy"
      else
        ""  # Vault not configured, skip check
      end
    end
  end
end
