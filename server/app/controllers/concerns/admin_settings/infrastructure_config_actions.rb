# frozen_string_literal: true

module AdminSettings
  module InfrastructureConfigActions
    extend ActiveSupport::Concern

    # GET /api/v1/admin_settings/infrastructure
    def infrastructure_config
      config = AdminSetting.redis_config
      # Mask password
      masked_config = config.dup
      masked_config["password"] = "••••••••" if masked_config["password"].present?

      # Get connection status
      connection_status = AdminSetting.test_redis_connection

      render_success(
        redis: masked_config,
        connection: connection_status
      )
    end

    # PUT /api/v1/admin_settings/infrastructure
    def update_infrastructure_config
      redis_params = infrastructure_params

      # Skip password update if masked value sent back
      redis_params.delete("password") if redis_params["password"] == "••••••••"

      AdminSetting.update_redis_config(redis_params)
      Powernode::Redis.reconfigure!

      log_audit_event("infrastructure_config_update", "SystemSettings",
                      metadata: { updated_fields: redis_params.keys })

      # Return updated config with masked password
      config = AdminSetting.redis_config
      config["password"] = "••••••••" if config["password"].present?

      render_success(
        redis: config,
        message: "Infrastructure configuration updated successfully"
      )
    rescue StandardError => e
      Rails.logger.error "Infrastructure config update failed: #{e.class.name}: #{e.message}"
      render_error("Failed to update infrastructure configuration: #{e.message}", :unprocessable_content)
    end

    # POST /api/v1/admin_settings/infrastructure/test_redis
    def test_redis_connection
      # Test with provided config or saved config
      test_config = if params[:redis].present?
        infrastructure_params
      else
        nil
      end

      result = AdminSetting.test_redis_connection(test_config)
      render_success(result)
    end

    # GET /api/v1/admin_settings/vault
    def vault_config
      connected = false
      health = {}

      begin
        vault_client = Security::VaultClient.instance
        health = vault_client.status || {}
        connected = health[:sealed] == false
      rescue StandardError => e
        Rails.logger.info("[AdminSettings] Vault unavailable: #{e.message}")
      end

      # Read from AdminSetting (UI-configured) first, fallback to ENV
      saved_config = begin
        raw = AdminSetting.get("vault_config")
        case raw
        when Hash then raw
        when String then raw.present? ? JSON.parse(raw) : {}
        else {}
        end
      rescue StandardError
        {}
      end

      vault_addr = saved_config["vault_addr"].presence || ENV["VAULT_ADDR"] || ""
      vault_role_id = saved_config["vault_role_id"].presence || ENV["VAULT_ROLE_ID"]
      vault_secret_id = saved_config["vault_secret_id"].presence || ENV["VAULT_SECRET_ID"]
      configured = vault_addr.present?

      # Mask credentials — show only last 4 chars
      masked_role = vault_role_id.present? ? ("••••" + vault_role_id[-4..]) : ""
      masked_secret = vault_secret_id.present? ? ("••••" + vault_secret_id[-4..]) : ""

      # Key management stats — sourced from whichever extension manages
      # cryptographic wallets/keys (e.g. a private extension) via the registry provider seam.
      # Core has no wallet/key concept, so it defaults to empty when no extension
      # registers a :vault_key_stats provider (core mode).
      key_stats = begin
        provider = Powernode::ExtensionRegistry.provider(:vault_key_stats)
        provider ? provider.summary : { secured_count: 0, recent_operations: [] }
      rescue StandardError => e
        Rails.logger.warn("[AdminSettings] vault_key_stats provider failed: #{e.message}")
        { secured_count: 0, recent_operations: [] }
      end
      wallet_key_count = key_stats[:secured_count]
      recent_key_ops = key_stats[:recent_operations]

      # NOTE: uses the data: keyword because the payload's :status key would
      # otherwise collide with render_success's HTTP-status keyword.
      render_success(
        data: {
          status: {
            connected: connected,
            sealed: health[:sealed],
            initialized: health[:initialized],
            version: health[:version],
            cluster_name: health[:cluster_name]
          },
          config: {
            vault_addr: vault_addr,
            vault_role_id: masked_role,
            vault_secret_id: masked_secret,
            configured: configured
          },
          keys: {
            secured_count: wallet_key_count,
            recent_operations: recent_key_ops
          }
        }
      )
    rescue StandardError => e
      Rails.logger.error("[AdminSettings] vault_config failed: #{e.class}: #{e.message}")
      render_error("Vault configuration check failed: #{e.message}", :internal_server_error)
    end

    # PUT /api/v1/admin_settings/vault
    def update_vault_config
      vault_params = params.require(:vault).permit(:vault_addr, :vault_role_id, :vault_secret_id)

      # Store in AdminSetting (persisted config)
      updates = {}
      updates["vault_addr"] = vault_params[:vault_addr] if vault_params[:vault_addr].present?
      updates["vault_role_id"] = vault_params[:vault_role_id] if vault_params[:vault_role_id].present? && vault_params[:vault_role_id] != "••••••••"
      updates["vault_secret_id"] = vault_params[:vault_secret_id] if vault_params[:vault_secret_id].present? && !vault_params[:vault_secret_id].start_with?("••••••••")

      AdminSetting.set("vault_config", updates.to_json) if updates.any?

      # Reset the VaultClient singleton so it re-reads config on next use
      Security::VaultClient.reconfigure! if updates.any?

      log_audit_event("vault_config_update", "SystemSettings",
                      metadata: { updated_fields: updates.keys })

      render_success(message: "Vault configuration updated and applied.")
    rescue StandardError => e
      render_error("Failed to update Vault configuration: #{e.message}", :unprocessable_content)
    end

    # POST /api/v1/admin_settings/vault/test
    def test_vault_connection
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      db_config = Security::VaultClient.admin_setting_config

      vault_addr = db_config["vault_addr"].presence || ENV["VAULT_ADDR"]
      role_id = db_config["vault_role_id"].presence || ENV["VAULT_ROLE_ID"]
      secret_id = db_config["vault_secret_id"].presence || ENV["VAULT_SECRET_ID"]

      unless vault_addr.present? && role_id.present? && secret_id.present?
        missing = []
        missing << "VAULT_ADDR" unless vault_addr.present?
        missing << "VAULT_ROLE_ID" unless role_id.present?
        missing << "VAULT_SECRET_ID" unless secret_id.present?
        return render_success(connected: false, error: "Missing: #{missing.join(', ')}")
      end

      # Test with a raw Vault client to get the actual error
      test_client = Vault::Client.new(
        address: vault_addr,
        ssl_verify: ENV.fetch("VAULT_SKIP_VERIFY", "false") != "true"
      )
      test_client.auth.approle(role_id, secret_id)
      health = test_client.sys.health_status
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

      # Extract values from HealthStatus (v0.20.0 uses instance variables, not methods)
      sealed = health.instance_variable_get(:@sealed)
      initialized = health.instance_variable_get(:@initialized)
      version = health.instance_variable_get(:@version)

      # Refresh singleton with successful config
      Security::VaultClient.reconfigure!

      payload = {
        connected: sealed == false,
        sealed: sealed,
        initialized: initialized,
        version: version,
        latency_ms: latency_ms
      }

      # The path probe runs ONLY once Vault is confirmed reachable and unsealed.
      # A sealed or unreachable Vault returns above/below without it, so the
      # four operator-visible cases stay distinct rather than collapsing into
      # one "not ok": unreachable / sealed / path-absent / wrong-shape.
      payload.merge!(probe_credential_path) if params[:path].present? && sealed == false

      render_success(**payload)
    rescue Vault::HTTPConnectionError
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)
      render_success(connected: false, error: "Cannot reach Vault at #{vault_addr}", latency_ms: latency_ms)
    rescue StandardError => e
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)
      render_success(connected: false, error: e.message.truncate(200), latency_ms: latency_ms)
    end

    private

    # Answers the two questions #test_vault_connection could not: does a KV
    # path RESOLVE, and does its payload carry the keys a caller needs. Filed
    # as IMP-0f914db2c7cf from the GitOps side, where a repository's
    # `vault_credential_path` holding the wrong keys surfaced as a git
    # authentication error with no Vault anywhere in it.
    #
    # ABSOLUTE: reports PRESENCE, SHAPE and KEY NAMES. It must never return,
    # log or echo a credential VALUE — `credential_keys` is `data.keys`, and
    # nothing here touches `data.values`. Preserve that if you extend it.
    #
    # Generic by construction: the caller supplies `required_keys`, so no
    # subsystem's key vocabulary lives in core. A GitOps repository advertises
    # its own set as `required_credential_keys`; a package repository can pass
    # a different one.
    #
    # Fails CLOSED — no arm returns `shape_ok: true` without having positively
    # compared a NON-EMPTY required-key set against real payload data. With no
    # requirement to compare there is nothing to pass, so the verdict is `nil`
    # (declined) rather than `true`; `true` there would be a pass mark awarded
    # for no test, and would make this an unqualified key-name enumerator for
    # any readable path. A read error is likewise distinguished from an absent
    # path (`path_present: nil` vs `false`) rather than reported as "missing".
    def probe_credential_path
      path = params[:path].to_s
      required = params[:required_keys].is_a?(Array) ? params[:required_keys].map(&:to_s).reject(&:blank?) : []
      base = { credential_path: path, required_keys: required }

      # probe_secret, NOT read_secret: it must not drive the shared Vault
      # circuit breaker (see Security::VaultClient#probe_secret). It also reads
      # uncached and invalidates the path, so the next sync cannot disagree
      # with what this reported.
      data = Security::VaultClient.probe_secret(path)

      unless data.is_a?(Hash)
        return base.merge(path_present: true, shape_ok: false,
                          path_error: "Payload at #{path} is not a key/value map (got #{data.class})")
      end

      present = data.keys.map(&:to_s).sort
      # A present-but-blank value is the same failure wearing a different mask,
      # and `require_creds!` on the sync side rejects it for the same reason:
      # key presence is not the property, a usable value is.
      missing = required.reject { |k| data[k].to_s.present? }

      verdict = base.merge(path_present: true, credential_keys: present)
      return verdict.merge(shape_ok: nil, path_error: "No required_keys supplied — key names reported, shape NOT checked") if required.empty?

      verdict.merge(missing_keys: missing, shape_ok: missing.empty?)
    rescue Security::VaultClient::SecretNotFoundError
      base.merge(path_present: false, shape_ok: false,
                 path_error: "No secret at #{path}")
    rescue StandardError => e
      # Keep the TAIL. Vault::HTTPError leads with ~140 characters of
      # boilerplate ("The Vault server at `<addr>' responded with a <code>...")
      # before the errors list, so a leading truncate discards the one line
      # that says WHY. Vault's message carries only address, status code and
      # its own server-generated error strings — never request or secret data.
      base.merge(path_present: nil, shape_ok: false,
                 path_error: e.message.length > 200 ? "...#{e.message.last(197)}" : e.message)
    end

    def infrastructure_params
      params.require(:redis).permit(
        :host, :port, :database, :password, :ssl, :url,
        :connect_timeout, :read_timeout, :write_timeout, :pool_size
      ).to_h
    end
  end
end
