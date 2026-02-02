# frozen_string_literal: true

module Security
  class VaultClient
    class VaultError < StandardError; end
    class AuthenticationError < VaultError; end
    class SecretNotFoundError < VaultError; end
    class ConnectionError < VaultError; end

    CACHE_TTL = 5.minutes
    MAX_RETRIES = 3
    RETRY_DELAY = 0.5.seconds
    CIRCUIT_BREAKER_THRESHOLD = 3
    CIRCUIT_BREAKER_TIMEOUT = 30.seconds

    attr_reader :client

    def initialize(token: nil)
      @address = ENV.fetch("VAULT_ADDR", "https://vault.powernode.internal:8200")
      @skip_verify = ENV.fetch("VAULT_SKIP_VERIFY", "false") == "true"
      @cache = Rails.cache
      @circuit_state = :closed
      @failure_count = 0
      @last_failure_time = nil

      configure_client(token)
    end

    # Read secret with caching
    def read_secret(path, key: nil, cache: true)
      check_circuit_breaker!

      cache_key = "vault:#{path}:#{key}"

      if cache && (cached = @cache.read(cache_key))
        return cached
      end

      result = with_retry do
        secret = @client.logical.read(path)
        raise SecretNotFoundError, "Secret not found: #{path}" unless secret

        data = extract_secret_data(secret)
        key ? data[key.to_sym] || data[key.to_s] : data
      end

      @cache.write(cache_key, result, expires_in: CACHE_TTL) if cache
      record_success!
      result
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure!
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Write secret
    def write_secret(path, data)
      check_circuit_breaker!

      with_retry do
        @client.logical.write(path, data: data.merge(stored_at: Time.current.iso8601))
      end

      # Invalidate cache
      invalidate_cache_for_path(path)
      record_success!
      path
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure!
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Delete secret
    def delete_secret(path)
      check_circuit_breaker!

      with_retry do
        @client.logical.delete(path)
      end

      invalidate_cache_for_path(path)
      record_success!
      true
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure!
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # List secrets at path
    def list_secrets(path)
      check_circuit_breaker!

      with_retry do
        result = @client.logical.list(path)
        result&.data&.[](:keys) || []
      end
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure!
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Generate short-lived token for container execution
    def generate_container_token(account_id:, execution_id:, ttl: "1h")
      check_circuit_breaker!

      with_retry do
        response = @client.auth_token.create(
          policies: [ "container-execution" ],
          ttl: ttl,
          renewable: false,
          metadata: {
            account_id: account_id,
            execution_id: execution_id,
            created_at: Time.current.iso8601
          },
          no_parent: true  # Orphan token for isolation
        )

        record_success!
        {
          token: response.auth.client_token,
          token_accessor: response.auth.accessor,
          ttl: response.auth.lease_duration
        }
      end
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure!
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Revoke a token (cleanup after container execution)
    def revoke_token(accessor:)
      check_circuit_breaker!

      with_retry do
        @client.auth_token.revoke_accessor(accessor)
      end

      record_success!
      true
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      Rails.logger.warn "Failed to revoke Vault token: #{e.message}"
      false
    end

    # Store account credential in Vault
    def store_credential(account_id:, credential_type:, credential_id:, data:)
      path = build_credential_path(account_id, credential_type, credential_id)
      write_secret(path, data)
      path
    end

    # Retrieve account credential
    def get_credential(account_id:, credential_type:, credential_id:, cache: true)
      path = build_credential_path(account_id, credential_type, credential_id)
      read_secret(path, cache: cache)
    rescue SecretNotFoundError
      nil
    end

    # Delete account credential
    def delete_credential(account_id:, credential_type:, credential_id:)
      path = build_credential_path(account_id, credential_type, credential_id)
      delete_secret(path)
    end

    # Rotate credential with version history
    def rotate_credential(account_id:, credential_type:, credential_id:, new_data:)
      path = build_credential_path(account_id, credential_type, credential_id)

      # KV v2 automatically versions
      write_secret(path, new_data.merge(
        rotated_at: Time.current.iso8601,
        previous_version: read_current_version(path)
      ))
    end

    # Store system secret
    def store_system_secret(name, data)
      path = "secret/data/powernode/system/#{name}"
      write_secret(path, data)
    end

    # Retrieve system secret
    def get_system_secret(name, key: nil, cache: true)
      path = "secret/data/powernode/system/#{name}"
      read_secret(path, key: key, cache: cache)
    end

    # Health check
    def healthy?
      return false if circuit_open?

      health = @client.sys.health_status
      health.sealed == false && health.initialized == true
    rescue StandardError => e
      Rails.logger.warn "Vault health check failed: #{e.message}"
      false
    end

    # Seal status
    def sealed?
      @client.sys.health_status.sealed
    rescue StandardError
      true  # Assume sealed if we can't connect
    end

    # Get Vault status info
    def status
      health = @client.sys.health_status
      {
        initialized: health.initialized,
        sealed: health.sealed,
        standby: health.standby,
        server_time_utc: health.server_time_utc,
        version: health.version,
        cluster_name: health.cluster_name,
        circuit_state: @circuit_state
      }
    rescue StandardError => e
      {
        error: e.message,
        circuit_state: @circuit_state,
        available: false
      }
    end

    # Wrap a sensitive operation with automatic Vault secret injection
    def with_secrets(paths, &block)
      secrets = paths.each_with_object({}) do |(key, path), hash|
        hash[key] = read_secret(path)
      end

      block.call(secrets)
    end

    private

    def configure_client(token)
      @client = Vault::Client.new(
        address: @address,
        token: token || fetch_app_token,
        ssl_verify: !@skip_verify
      )

      # Configure CA cert if provided
      ca_cert = ENV["VAULT_CA_CERT"]
      @client.ssl_ca_cert = ca_cert if ca_cert.present?
    rescue StandardError => e
      Rails.logger.error "Failed to configure Vault client: #{e.message}"
      raise AuthenticationError, "Vault configuration failed: #{e.message}"
    end

    def fetch_app_token
      # Use AppRole authentication
      role_id = ENV.fetch("VAULT_ROLE_ID") do
        raise AuthenticationError, "VAULT_ROLE_ID environment variable not set"
      end

      secret_id = ENV.fetch("VAULT_SECRET_ID") do
        raise AuthenticationError, "VAULT_SECRET_ID environment variable not set"
      end

      auth_client = Vault::Client.new(
        address: @address,
        ssl_verify: !@skip_verify
      )

      response = auth_client.auth.approle.login(role_id, secret_id)
      response.auth.client_token
    rescue Vault::HTTPError => e
      raise AuthenticationError, "Vault AppRole authentication failed: #{e.message}"
    end

    def build_credential_path(account_id, credential_type, credential_id)
      "secret/data/powernode/accounts/#{account_id}/#{credential_type}/#{credential_id}"
    end

    def extract_secret_data(secret)
      # Handle KV v2 response format
      if secret.data.key?(:data)
        secret.data[:data]
      else
        secret.data
      end
    end

    def read_current_version(path)
      metadata_path = path.sub("/data/", "/metadata/")
      metadata = @client.logical.read(metadata_path)
      metadata&.data&.dig(:current_version)
    rescue StandardError
      nil
    end

    def invalidate_cache_for_path(path)
      # Invalidate all cached entries for this path
      @cache.delete_matched("vault:#{path}:*")
      @cache.delete("vault:#{path}:")
    end

    def with_retry(retries: MAX_RETRIES)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue Vault::HTTPConnectionError, Vault::HTTPError => e
        if attempts < retries && retryable_error?(e)
          sleep(RETRY_DELAY * attempts)
          retry
        end
        raise
      end
    end

    def retryable_error?(error)
      # Retry on connection errors and 5xx responses
      error.is_a?(Vault::HTTPConnectionError) ||
        (error.respond_to?(:code) && error.code.to_i >= 500)
    end

    # Circuit breaker implementation
    def check_circuit_breaker!
      case @circuit_state
      when :open
        if Time.current - @last_failure_time > CIRCUIT_BREAKER_TIMEOUT
          @circuit_state = :half_open
        else
          raise ConnectionError, "Vault circuit breaker is open - service unavailable"
        end
      when :half_open
        # Allow one request to test
      end
    end

    def circuit_open?
      @circuit_state == :open
    end

    def record_success!
      @failure_count = 0
      @circuit_state = :closed
    end

    def record_failure!
      @failure_count += 1
      @last_failure_time = Time.current

      if @failure_count >= CIRCUIT_BREAKER_THRESHOLD
        @circuit_state = :open
        Rails.logger.error "Vault circuit breaker opened after #{@failure_count} failures"
      end
    end

    class << self
      def instance
        @instance ||= new
      end

      delegate :read_secret, :write_secret, :delete_secret, :list_secrets,
               :store_credential, :get_credential, :delete_credential, :rotate_credential,
               :store_system_secret, :get_system_secret,
               :generate_container_token, :revoke_token,
               :healthy?, :sealed?, :status, :with_secrets,
               to: :instance
    end
  end
end
