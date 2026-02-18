# frozen_string_literal: true

module BaaS
  class ApiKeyService
    attr_reader :tenant

    def initialize(tenant:)
      @tenant = tenant
    end

    # Create a new API key
    def create_key(params)
      return { success: false, error: "Tenant not found" } unless tenant

      key_type = params[:key_type] || "secret"
      environment = params[:environment] || tenant.environment

      # Generate the raw key
      raw_key = BaaS::ApiKey.generate_key(type: key_type, environment: environment)
      key_hash = BaaS::ApiKey.hash_key(raw_key)
      key_prefix = raw_key[0..11] # First 12 chars as prefix for identification

      api_key = tenant.api_keys.build(
        name: params[:name],
        key_prefix: key_prefix,
        key_hash: key_hash,
        key_type: key_type,
        environment: environment,
        scopes: params[:scopes] || [ "*" ],
        rate_limit_per_minute: params[:rate_limit_per_minute] || 100,
        rate_limit_per_day: params[:rate_limit_per_day] || 10_000,
        expires_at: params[:expires_at],
        metadata: params[:metadata] || {}
      )

      if api_key.save
        Rails.logger.info "API key created for tenant #{tenant.id}: #{key_prefix}"
        # Return the raw key only on creation - it cannot be retrieved later
        { success: true, api_key: api_key, raw_key: raw_key }
      else
        { success: false, errors: api_key.errors.full_messages }
      end
    end

    # List all API keys for tenant
    def list_keys(params = {})
      return { success: false, error: "Tenant not found" } unless tenant

      keys = tenant.api_keys
      keys = keys.for_environment(params[:environment]) if params[:environment].present?
      keys = keys.where(key_type: params[:key_type]) if params[:key_type].present?
      keys = keys.where(status: params[:status]) if params[:status].present?

      keys = keys.order(created_at: :desc)

      { success: true, api_keys: keys.map(&:summary) }
    end

    # Get a specific API key
    def get_key(key_id)
      return { success: false, error: "Tenant not found" } unless tenant

      api_key = tenant.api_keys.find_by(id: key_id)
      return { success: false, error: "API key not found" } unless api_key

      { success: true, api_key: api_key.summary }
    end

    # Update an API key
    def update_key(key_id, params)
      return { success: false, error: "Tenant not found" } unless tenant

      api_key = tenant.api_keys.find_by(id: key_id)
      return { success: false, error: "API key not found" } unless api_key
      return { success: false, error: "Cannot update revoked key" } if api_key.revoked?

      allowed_params = params.slice(
        :name, :scopes, :rate_limit_per_minute, :rate_limit_per_day,
        :expires_at, :metadata
      )

      if api_key.update(allowed_params)
        { success: true, api_key: api_key.summary }
      else
        { success: false, errors: api_key.errors.full_messages }
      end
    end

    # Revoke an API key
    def revoke_key(key_id)
      return { success: false, error: "Tenant not found" } unless tenant

      api_key = tenant.api_keys.find_by(id: key_id)
      return { success: false, error: "API key not found" } unless api_key
      return { success: false, error: "API key already revoked" } if api_key.revoked?

      api_key.revoke!
      Rails.logger.info "API key revoked: #{api_key.key_prefix}"
      { success: true, api_key: api_key.summary }
    end

    # Roll an API key (revoke and create new)
    def roll_key(key_id)
      return { success: false, error: "Tenant not found" } unless tenant

      old_key = tenant.api_keys.find_by(id: key_id)
      return { success: false, error: "API key not found" } unless old_key

      # Create new key with same settings
      result = create_key(
        name: old_key.name,
        key_type: old_key.key_type,
        environment: old_key.environment,
        scopes: old_key.scopes,
        rate_limit_per_minute: old_key.rate_limit_per_minute,
        rate_limit_per_day: old_key.rate_limit_per_day,
        expires_at: old_key.expires_at,
        metadata: old_key.metadata.merge(rolled_from: old_key.id)
      )

      return result unless result[:success]

      # Revoke old key
      old_key.revoke!

      Rails.logger.info "API key rolled: #{old_key.key_prefix} -> #{result[:api_key].key_prefix}"
      {
        success: true,
        api_key: result[:api_key],
        raw_key: result[:raw_key],
        old_key_id: old_key.id
      }
    end

    # Validate an API key and return tenant
    def self.authenticate(raw_key)
      return { success: false, error: "API key required" } if raw_key.blank?

      api_key = BaaS::ApiKey.find_by_key(raw_key)
      return { success: false, error: "Invalid API key" } unless api_key

      # Check expiration
      api_key.check_expiration!
      return { success: false, error: "API key expired" } if api_key.expired?
      return { success: false, error: "API key revoked" } if api_key.revoked?

      tenant = api_key.baas_tenant
      return { success: false, error: "Tenant suspended" } if tenant.suspended?
      return { success: false, error: "Tenant not active" } unless tenant.active?

      # Check rate limits
      unless tenant.can_make_api_request?
        return { success: false, error: "Rate limit exceeded" }
      end

      # Record usage
      api_key.record_usage!
      tenant.record_api_request!

      { success: true, tenant: tenant, api_key: api_key }
    end

    # Check if key has required scope
    def self.authorize(api_key, required_scope)
      return false unless api_key
      api_key.has_scope?(required_scope)
    end
  end
end
