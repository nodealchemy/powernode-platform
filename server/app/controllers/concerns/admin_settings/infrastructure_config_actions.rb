# frozen_string_literal: true

module AdminSettings
  module InfrastructureConfigActions
    extend ActiveSupport::Concern

    # GET /api/v1/admin_settings/infrastructure
    def infrastructure_config
      config = ::Admin::SystemSettings.redis_config

      # Get connection status (uses the REAL config, not the masked one below)
      connection_status = AdminSetting.test_redis_connection(config)

      render_success(
        redis: mask_secret_field(config, "password"),
        connection: connection_status
      )
    end

    # PUT /api/v1/admin_settings/infrastructure
    def update_infrastructure_config
      redis_params = infrastructure_params

      # fc-38 review round 3 item #3(b): clear_password: true is the
      # explicit "remove this credential" signal a blank password can't be
      # (a blank value means "unchanged" — see unchanged_secret_value?
      # below). Stripped out of redis_params before it reaches
      # Admin::SystemSettings, which takes it as its own keyword instead —
      # this concern owns request-param shape, that method owns storage.
      clear_password = ActiveModel::Type::Boolean.new.cast(redis_params.delete("clear_password"))

      # fc-38 review round 3 item #3(a): a mask-shaped resubmission used to
      # be silently dropped while the response still reported success — a
      # caller (a stale client, or a genuine mistake) had no way to
      # distinguish "your edit was ignored" from "your edit was saved". A
      # BLANK value still means "unchanged" (the field wasn't touched) and
      # is silently skipped below; a value that positively LOOKS like the
      # display mask is a caller error and gets a 422 instead of a lie. Not
      # checked when clearing — clear_password already says what to do with
      # the field, so a stray mask-shaped value alongside it is moot.
      if !clear_password && masked_secret_value?(redis_params["password"])
        return render_error(
          "The password field still holds the masked display value — enter a new password to change it.",
          :unprocessable_content
        )
      end

      redis_params.delete("password") if clear_password || unchanged_secret_value?(redis_params["password"])

      ::Admin::SystemSettings.update_redis_config!(redis_params, clear_password: clear_password)
      Powernode::Redis.reconfigure!

      log_audit_event("infrastructure_config_update", "SystemSettings",
                      metadata: { updated_fields: redis_params.keys, cleared_password: clear_password })

      config = ::Admin::SystemSettings.redis_config

      render_success(
        redis: mask_secret_field(config, "password"),
        message: "Infrastructure configuration updated successfully"
      )
    rescue StandardError => e
      Rails.logger.error "Infrastructure config update failed: #{e.class.name}: #{e.message}"
      render_error("Failed to update infrastructure configuration: #{e.message}", :unprocessable_content)
    end

    # POST /api/v1/admin_settings/infrastructure/test_redis
    def test_redis_connection
      # Test with the just-submitted config, or the REAL saved config
      # (::Admin::SystemSettings.redis_config, which includes the decrypted
      # password) — never AdminSetting.test_redis_connection(nil), whose
      # internal `config ||= redis_config` fallback reads the password-less
      # blob directly and would always report a failed/passwordless connection.
      test_config = params[:redis].present? ? infrastructure_params : ::Admin::SystemSettings.redis_config

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
      saved_config = ::Admin::SystemSettings.vault_config

      vault_addr = saved_config["vault_addr"].presence || ENV["VAULT_ADDR"] || ""
      vault_role_id = saved_config["vault_role_id"].presence || ENV["VAULT_ROLE_ID"]
      vault_secret_id = saved_config["vault_secret_id"].presence || ENV["VAULT_SECRET_ID"]
      configured = vault_addr.present?

      # Never return any part of a credential (fc-38 review item #1) — the
      # UI gets a "configured" boolean instead of a last-4-characters mask,
      # matching how email/redis now mask their secrets. See
      # #unchanged_secret_value? for why a last-4 mask was unsafe: the write
      # side had no reliable way to recognize it as "unchanged" and not a
      # real new credential.
      role_configured = vault_role_id.present?
      secret_configured = vault_secret_id.present?

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
            vault_role_id: "",
            vault_role_id_configured: role_configured,
            vault_secret_id: "",
            vault_secret_id_configured: secret_configured,
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
      vault_params = params.require(:vault).permit(
        :vault_addr, :vault_role_id, :vault_secret_id,
        :clear_vault_role_id, :clear_vault_secret_id
      )

      # fc-38 review round 3 item #3(b): the explicit "remove this
      # credential" signal a blank role_id/secret_id can't be (see
      # #update_infrastructure_config's clear_password for the same
      # reasoning on the redis side).
      clear_role = ActiveModel::Type::Boolean.new.cast(vault_params[:clear_vault_role_id])
      clear_secret = ActiveModel::Type::Boolean.new.cast(vault_params[:clear_vault_secret_id])

      # Store via Admin::SystemSettings — vault_role_id/vault_secret_id are
      # encrypted, vault_addr stays in the non-secret blob (fc-38 decision #3).
      # fc-38 review item #1 (HIGH): the old checks here (`!= "••••••••"`,
      # `!start_with?("••••••••")`) never matched vault's own
      # "••••<last4>" display mask, so resubmitting the loaded (masked) value
      # to save vault_addr alone silently overwrote both real AppRole
      # credentials with the display mask. #unchanged_secret_value? matches
      # ANY mask-shaped value, not one specific literal.
      # fc-38 review round 3 item #3(a): same silent-drop-with-success
      # problem as redis's password (see #update_infrastructure_config) — a
      # mask-shaped resubmission is a 422 now, not a quiet no-op. Not
      # checked when clearing that same field — see the redis-side comment.
      if !clear_role && masked_secret_value?(vault_params[:vault_role_id])
        return render_error(
          "The AppRole Role ID field still holds the masked display value — enter a new value to change it.",
          :unprocessable_content
        )
      end
      if !clear_secret && masked_secret_value?(vault_params[:vault_secret_id])
        return render_error(
          "The AppRole Secret ID field still holds the masked display value — enter a new value to change it.",
          :unprocessable_content
        )
      end

      updates = {}
      updates["vault_addr"] = vault_params[:vault_addr] if vault_params[:vault_addr].present?
      updates["vault_role_id"] = vault_params[:vault_role_id] if !clear_role && !unchanged_secret_value?(vault_params[:vault_role_id])
      updates["vault_secret_id"] = vault_params[:vault_secret_id] if !clear_secret && !unchanged_secret_value?(vault_params[:vault_secret_id])

      applied = updates.any? || clear_role || clear_secret
      ::Admin::SystemSettings.update_vault_config!(updates, clear_vault_role_id: clear_role, clear_vault_secret_id: clear_secret) if applied

      # Reset the VaultClient singleton so it re-reads config on next use
      Security::VaultClient.reconfigure! if applied

      log_audit_event("vault_config_update", "SystemSettings",
                      metadata: { updated_fields: updates.keys, cleared_role_id: clear_role, cleared_secret_id: clear_secret })

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
        :connect_timeout, :read_timeout, :write_timeout, :pool_size,
        :clear_password
      ).to_h
    end

    # A blank value, or one containing the mask character at all, is treated
    # as "the user didn't change this" (fc-38 review item #1) — not just an
    # exact "••••••••", and not just all-bullets: the OLD vault mask was
    # "••••" + the real value's last 4 characters, so a stale client caching
    # that shape could resend e.g. "••••abcd" as if it were a real
    # credential. A genuine credential containing "•" is vanishingly
    # unlikely, so matching on presence rather than an exact shape is the
    # safer default. The GET actions above never return any part of a secret
    # to resubmit in the first place, so a well-behaved caller has nothing
    # mask-shaped to send back at all — this is defense in depth for any
    # caller (or cached frontend build) that still does.
    def unchanged_secret_value?(value)
      value.blank? || value.to_s.include?("•")
    end

    # A non-blank value that still contains the mask character (fc-38 review
    # round 3 item #3(a)) — this is the "the caller resubmitted the display
    # mask" case specifically, distinct from a blank value (which just means
    # "this field wasn't touched"). Callers use this to return a 422 instead
    # of silently treating a caller's mistaken resubmission as "unchanged"
    # and reporting success.
    def masked_secret_value?(value)
      value.present? && value.to_s.include?("•")
    end

    # Never returns any part of `field`'s real value — "" plus a
    # "<field>_configured" boolean, so the UI can say "configured" without
    # holding a redisplayable fragment of the secret (fc-38 review item #1).
    def mask_secret_field(config, field)
      config.merge(field => "", "#{field}_configured" => config[field].present?)
    end
  end
end
