# frozen_string_literal: true

module Security
  class VaultClient
    include CircuitBreakerCore

    class VaultError < StandardError; end
    class AuthenticationError < VaultError; end
    class SecretNotFoundError < VaultError; end
    class ConnectionError < VaultError; end

    CACHE_TTL = 5.minutes
    MAX_RETRIES = 3
    RETRY_DELAY = 0.5.seconds

    attr_reader :client

    def initialize(token: nil)
      # Read from AdminSetting (UI-configured) first, fallback to ENV
      db_config = self.class.admin_setting_config
      @address = db_config["vault_addr"].presence || ENV.fetch("VAULT_ADDR", "https://vault.powernode.internal:8200")
      @skip_verify = ENV.fetch("VAULT_SKIP_VERIFY", "false") == "true"
      @cache = Rails.cache

      setup_circuit_breaker(
        resource_id: "vault",
        service_name: "security_vault",
        config: {
          failure_threshold: 3,
          success_threshold: 2,
          timeout_duration: 30_000,
          monitoring_window: 300_000,
          reset_timeout: 300_000
        }
      )

      configure_client(token)
    end

    # Read secret with caching
    def read_secret(path, key: nil, cache: true)
      check_circuit_breaker!

      cache_key = "vault:#{path}:#{key}"

      if cache && (cached = @cache.read(cache_key))
        return normalize_secret_data(cached)
      end

      result = with_retry do
        secret = @client.logical.read(path)
        raise SecretNotFoundError, "Secret not found: #{path}" unless secret

        data = extract_secret_data(secret)
        normalize_secret_data(key ? data[key.to_sym] || data[key.to_s] : data)
      end

      @cache.write(cache_key, result, expires_in: CACHE_TTL) if cache
      record_success
      result
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure(nil)
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Diagnostic sibling of #read_secret for "does this KV path resolve, and
    # what shape does it hold". Deliberately does NOT participate in the
    # circuit breaker: it neither calls check_circuit_breaker! nor records a
    # failure. A probe of a path this AppRole cannot read raises a
    # non-retryable Vault::HTTPError, which through #read_secret would count
    # against the shared `vault` breaker — three such probes would open it for
    # five minutes for EVERY Vault consumer in the platform. A diagnostic must
    # not be able to break the subsystem it diagnoses.
    #
    # Also uncached in both directions, and it INVALIDATES the path's cached
    # entries on success: a probe that reported a shape the next reader would
    # not see is the false reassurance this method exists to prevent, so the
    # probe is made authoritative for subsequent reads rather than merely
    # fresh for itself.
    #
    # Returns the same normalized (string-indexable) hash #read_secret returns,
    # via the same extract/normalize pair — the shape must not be a second
    # definition. Raises SecretNotFoundError when the path is absent.
    def probe_secret(path)
      secret = @client.logical.read(path)
      raise SecretNotFoundError, "Secret not found: #{path}" unless secret

      normalize_secret_data(extract_secret_data(secret)).tap do
        invalidate_cache_for_path(path)
      end
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
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
      record_success
      path
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure(nil)
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Delete secret
    def delete_secret(path)
      check_circuit_breaker!

      with_retry do
        @client.logical.delete(path)
      end

      invalidate_cache_for_path(path)
      record_success
      true
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure(nil)
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
      record_failure(nil)
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

        record_success
        {
          token: response.auth.client_token,
          token_accessor: response.auth.accessor,
          ttl: response.auth.lease_duration
        }
      end
    rescue Vault::HTTPConnectionError, Vault::HTTPError => e
      record_failure(nil)
      raise ConnectionError, "Vault connection error: #{e.message}"
    end

    # Revoke a token (cleanup after container execution)
    def revoke_token(accessor:)
      check_circuit_breaker!

      with_retry do
        @client.auth_token.revoke_accessor(accessor)
      end

      record_success
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
      health.instance_variable_get(:@sealed) == false && health.instance_variable_get(:@initialized) == true
    rescue StandardError => e
      Rails.logger.warn "Vault health check failed: #{e.message}"
      false
    end

    # Seal status
    def sealed?
      @client.sys.health_status.instance_variable_get(:@sealed)
    rescue StandardError
      true  # Assume sealed if we can't connect
    end

    # Get Vault status info
    def status
      health = @client.sys.health_status
      {
        initialized: health.instance_variable_get(:@initialized),
        sealed: health.instance_variable_get(:@sealed),
        standby: health.instance_variable_get(:@standby),
        server_time_utc: health.instance_variable_get(:@server_time_utc),
        version: health.instance_variable_get(:@version),
        cluster_name: health.instance_variable_get(:@cluster_name),
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
      # Use AppRole authentication — read from AdminSetting first, fallback to ENV
      db_config = self.class.admin_setting_config
      role_id = db_config["vault_role_id"].presence || ENV["VAULT_ROLE_ID"]
      secret_id = db_config["vault_secret_id"].presence || ENV["VAULT_SECRET_ID"]

      raise AuthenticationError, "VAULT_ROLE_ID not configured (set in UI or environment)" unless role_id.present?
      raise AuthenticationError, "VAULT_SECRET_ID not configured (set in UI or environment)" unless secret_id.present?

      auth_client = Vault::Client.new(
        address: @address,
        ssl_verify: !@skip_verify
      )

      response = auth_client.auth.approle(role_id, secret_id)
      response.auth.client_token
    rescue Vault::HTTPError => e
      raise AuthenticationError, "Vault AppRole authentication failed: #{e.message}"
    end

    def build_credential_path(account_id, credential_type, credential_id)
      "secret/data/powernode/accounts/#{account_id}/#{credential_type}/#{credential_id}"
    end

    # Make #read_secret's no-key branch agree with its single-key branch on how
    # a caller may spell a key.
    #
    # The vault gem parses every response with `symbolize_names: true`
    # (vault-0.20.1 lib/vault/client.rb JSON_PARSE_OPTIONS, applied at :388 and
    # :422), so #extract_secret_data always yields a SYMBOL-keyed Hash, while a
    # cache round-trip through a JSON-coded store yields STRING keys. The
    # single-key branch already tolerated both (`data[key.to_sym] ||
    # data[key.to_s]`); the no-key branch returned the raw Hash, so a caller
    # indexing it with strings read nil for every field — silently, since a
    # wrong-keyed Hash is truthy and non-empty. Returning a
    # HashWithIndifferentAccess makes both branches, and both cache states, read
    # the same. Non-Hash values (the single-key branch's usual scalar) pass
    # through untouched.
    #
    # Applied to the single-key branch too, and not only the no-key one:
    # `symbolize_names` is DEEP, so a single-key read whose VALUE is itself a
    # Hash would otherwise come back symbol-keyed on a cache MISS and
    # indifferent on the following HIT — a worse failure than a consistently
    # wrong one, because it only reproduces once per cache window.
    def normalize_secret_data(data)
      data.is_a?(Hash) ? data.with_indifferent_access : data
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

    def check_circuit_breaker!
      unless allow_request?
        raise ConnectionError, "Vault circuit breaker is open - service unavailable"
      end
    end

    def circuit_open?
      circuit_state == "open"
    end

    class << self
      def instance
        @instance ||= new
      end

      # Reset the singleton — called after Vault config is updated via UI
      def reconfigure!
        @instance = nil
      end

      # Read Vault config from AdminSetting (DB-persisted, set via UI)
      def admin_setting_config
        return @_admin_config if defined?(@_admin_config) && @_admin_config_at && @_admin_config_at > 1.minute.ago

        raw = defined?(AdminSetting) ? AdminSetting.get("vault_config") : nil
        @_admin_config = case raw
        when Hash then raw
        when String then raw.present? ? JSON.parse(raw) : {}
        else {}
        end
        @_admin_config_at = Time.current
        @_admin_config
      rescue StandardError
        {}
      end

      delegate :read_secret, :probe_secret, :write_secret, :delete_secret, :list_secrets,
               :store_credential, :get_credential, :delete_credential, :rotate_credential,
               :store_system_secret, :get_system_secret,
               :generate_container_token, :revoke_token,
               :with_secrets,
               to: :instance

      # Availability probes MUST NOT raise — callers across the codebase
      # (VaultCredentialProvider, controllers) treat "Vault unconfigured" the
      # same as "Vault unavailable" and fall back to DB encryption. `instance`
      # (`@instance ||= new`) raises Security::VaultClient::AuthenticationError
      # while constructing the Vault::Client — the AppRole login in
      # #fetch_app_token — whenever VAULT_ROLE_ID/VAULT_SECRET_ID are absent
      # (a Vault-less deployment, e.g. ops-hub, by design). A plain `delegate`
      # would let that escape past the instance-level rescues in #healthy? /
      # #sealed? / #status below, since those only guard the health-check
      # call itself, not client configuration. Fail closed instead.
      def sealed?
        instance.sealed?
      rescue StandardError => e
        Rails.logger.warn "Vault unavailable, treating as sealed: #{e.message}"
        true
      end

      def healthy?
        instance.healthy?
      rescue StandardError => e
        Rails.logger.warn "Vault unavailable: #{e.message}"
        false
      end

      def status
        instance.status
      rescue StandardError => e
        { error: e.message, circuit_state: "unknown", available: false }
      end
    end
  end
end
