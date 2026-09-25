# frozen_string_literal: true

module Admin
  # Single point of contact for every General/Email/Proxy AdminSetting read
  # and write (fc-38). Before this, five controllers wrote AdminSetting
  # directly and config_controller.rb read two of those same keys back with
  # its own copy of the string->bool parsing logic.
  #
  # Explicitly OUT of scope, unchanged by this class:
  #   - Admin::MaintenanceMode (fc-03) — its own store, kept as-is.
  #   - AdminSettings::ExtensionActions / ::SecurityConfigActions /
  #     ::InfrastructureConfigActions concerns — none of them touch
  #     AdminSetting (Flipper/FeatureGateService, Rails.cache, and the
  #     redis_config/vault_config keys respectively — the latter is being
  #     hardened separately, see fc-38 decision #3).
  class SystemSettings
    # The flat, non-secret keys AdminSettingsController#update accepts.
    # rate_limiting/system_notifications/feature_flags are intentionally not
    # listed here — they are Hash-valued and fan out to dotted sub-keys (see
    # .update_general_settings!), so a flat allowlist doesn't apply to them.
    GENERAL_KEYS = %w[
      registration_enabled email_verification_required require_email_verification
      password_complexity_level session_timeout_minutes max_failed_login_attempts
      account_lockout_duration system_name system_email support_email platform_url
      trial_period_days payment_retry_attempts webhook_timeout_seconds
      allow_account_deletion copyright_text
    ].freeze

    # Pins the exact string->bool mapping config_controller.rb used before
    # this moved here, so an operator's already-stored value keeps meaning
    # the same thing (fc-38 decision #6).
    TRUE_STRINGS = %w[true 1 yes on enabled].freeze
    FALSE_STRINGS = %w[false 0 no off disabled].freeze

    # The rate_limiting sub-fields AdminSettingsController#update permits,
    # stored under "rate_limiting.<key>" (see .update_general_settings! and
    # .rate_limit / .rate_limiting_config below).
    RATE_LIMIT_KEYS = %w[
      enabled api_requests_per_minute login_attempts_per_hour registration_attempts_per_hour
      password_reset_attempts_per_hour email_verification_attempts_per_hour
      authenticated_requests_per_hour impersonation_attempts_per_hour
      webhook_requests_per_minute websocket_connections_per_minute
    ].freeze

    # Raised when a value that reached .update_general_settings! is neither a
    # scalar nor a Hash of scalars — a caller must never see it silently
    # `.to_s`'d into storage (fc-38 decision #1). The controller's existing
    # `rescue StandardError` renders this as a 422.
    NonScalarSettingValue = Class.new(StandardError)

    class << self
      # -- General ------------------------------------------------------------

      # Raw string values (nil when unset) for the flat keys in GENERAL_KEYS.
      def general_settings
        GENERAL_KEYS.index_with { |key| AdminSetting.find_by(key: key)&.value }
      end

      # `settings_params` MUST already be a plain Hash — the caller
      # (AdminSettingsController#update) normalizes at the request boundary
      # via `.to_h` before calling this, because a permitted nested param
      # comes back from Rails as an ActionController::Parameters, which
      # `is_a?(Hash)` never matches (fc-38: this was the actual cause of
      # rate_limiting/system_notifications/feature_flags never persisting —
      # see db/migrate/20260925010000_delete_garbage_admin_settings_
      # nested_writer_rows.rb). This class has no dependency on
      # ActionController and must never be handed one.
      #
      # A flat key writes its `.to_s` directly; a Hash value (currently only
      # rate_limiting) fans out to "key.sub_key" rows. Returns the flat map
      # of what was written (original, un-stringified values), the same
      # shape the controller already renders back to the caller.
      #
      # A value that is itself non-scalar (an Array, or a Hash nested more
      # than one level deep) raises NonScalarSettingValue rather than being
      # silently stringified — the flat `.to_s` fallback that used to catch
      # this (and, before the boundary fix, caught EVERY nested Hash) is gone.
      def update_general_settings!(settings_params)
        updated = {}

        settings_params.each do |key, value|
          case value
          when Hash
            value.each do |sub_key, sub_value|
              raise NonScalarSettingValue, "#{key}.#{sub_key} must be a scalar value" if non_scalar?(sub_value)

              setting_key = "#{key}.#{sub_key}"
              AdminSetting.find_or_initialize_by(key: setting_key).update!(value: sub_value.to_s)
              updated[setting_key] = sub_value
            end
          when Array
            raise NonScalarSettingValue, "#{key} must be a scalar or a Hash of scalars, got an Array"
          else
            AdminSetting.find_or_initialize_by(key: key.to_s).update!(value: value.to_s)
            updated[key] = value
          end
        end

        updated
      end

      # -- Rate limiting ----------------------------------------------------

      # Single-field read used by the readers that report/enforce a
      # configured limit (RateLimitingController#extract_limit_from_key,
      # Admin::SettingsService#check_unusual_api_activity,
      # RateLimiting::BaseService#extract_limit_from_key/
      # #get_current_configuration). nil when unset, matching the pre-move
      # `AdminSetting.find_by(key: ...)&.value&.to_i` contract exactly.
      def rate_limit(key)
        AdminSetting.find_by(key: "rate_limiting.#{key}")&.value&.to_i
      end

      # Rebuilds the nested hash the settings form expects from the dotted
      # rows .update_general_settings! wrote — the GET/show path this backs
      # (Admin::SettingsService#settings_summary_data) used to dump AdminSetting
      # rows RAW, so before fc-38 this key was either absent or the garbage
      # stringified-Parameters value; now it is the typed hash actually saved.
      # A field with no row yet is nil, matching what
      # RateLimitingSettings.tsx's own per-field fallbacks (`?? true`,
      # `|| 60`) already expect.
      def rate_limiting_config
        RATE_LIMIT_KEYS.each_with_object({}) do |key, hash|
          setting = AdminSetting.find_by(key: "rate_limiting.#{key}")
          hash[key] = setting && (key == "enabled" ? parse_boolean_string(setting.value, default: true) : setting.value.to_i)
        end
      end

      # config_controller.rb's public /config payload — folded in per fc-38
      # decision #6, same default-true-on-anything-unclear behavior.
      def registration_enabled?
        typed_boolean("registration_enabled", default: true)
      end

      def email_verification_required?
        typed_boolean("email_verification_required", default: true)
      end

      # -- Email ----------------------------------------------------------
      #
      # Always returns the DECRYPTED value — masking is the caller's decision
      # (EmailSettingsController's worker-identity reveal gate is a
      # request-scoped concern this class has no visibility into; see fc-38
      # decision #3, "Email keeps CredentialEncryptionService exactly as is,
      # behind the new service, with the same masking and reveal gate").

      def email_settings
        {
          provider: AdminSetting.get("email_provider", "smtp"),
          smtp_enabled: AdminSetting.get("smtp_enabled", false),
          smtp_host: AdminSetting.get("smtp_host", ""),
          smtp_port: AdminSetting.get("smtp_port", 587),
          smtp_username: AdminSetting.get("smtp_username", ""),
          smtp_password: decrypt_secret(AdminSetting.get("smtp_password_encrypted", "")),
          smtp_encryption: AdminSetting.get("smtp_encryption", "tls"),
          smtp_authentication: AdminSetting.get("smtp_authentication", true),
          smtp_from_address: AdminSetting.get("smtp_from_address", "noreply@powernode.dev"),
          smtp_from_name: AdminSetting.get("smtp_from_name", "Powernode"),
          smtp_domain: AdminSetting.get("smtp_domain", "powernode.dev"),

          sendgrid_api_key: decrypt_secret(AdminSetting.get("sendgrid_api_key_encrypted", "")),
          ses_access_key: AdminSetting.get("ses_access_key", ""),
          ses_secret_key: decrypt_secret(AdminSetting.get("ses_secret_key_encrypted", "")),
          ses_region: AdminSetting.get("ses_region", "us-east-1"),
          mailgun_api_key: decrypt_secret(AdminSetting.get("mailgun_api_key_encrypted", "")),
          mailgun_domain: AdminSetting.get("mailgun_domain", ""),

          email_verification_expiry_hours: AdminSetting.email_verification_expiry_hours,
          password_reset_expiry_hours: AdminSetting.get("password_reset_expiry_hours", 2),
          max_email_retries: AdminSetting.get("max_email_retries", 3),
          email_retry_delay_seconds: AdminSetting.get("email_retry_delay_seconds", 60)
        }
      end

      # Mirrors EmailSettingsController#update's pre-move write loop exactly:
      # a `_password`/`_api_key`/`_secret_key`-suffixed key is encrypted
      # before storage via Security::CredentialEncryptionService (unchanged —
      # fc-38 decision #3), everything else is a plain AdminSetting.set. The
      # "provider" -> "email_provider" key normalization is preserved too.
      def update_email_settings!(permitted_params)
        permitted_params.each do |key, value|
          setting_key = key.to_s == "provider" ? "email_provider" : key.to_s

          if setting_key.end_with?("_password", "_api_key", "_secret_key")
            AdminSetting.set("#{setting_key}_encrypted", encrypt_secret(value))
          else
            AdminSetting.set(setting_key, value)
          end
        end
      end

      # Backward compatibility, preserved from the pre-move controller: a
      # value written before encryption was added was stored as plaintext and
      # cannot be decrypted. Treat it as its literal value so an existing
      # config keeps sending mail until the next save re-encrypts it.
      def decrypt_secret(encrypted_value)
        return "" if encrypted_value.blank?

        ::Security::CredentialEncryptionService.decrypt_value(encrypted_value).to_s
      rescue ::Security::CredentialEncryptionService::DecryptionError
        encrypted_value
      end

      def encrypt_secret(value)
        return "" if value.blank?

        ::Security::CredentialEncryptionService.encrypt_value(value)
      end

      # -- Proxy ------------------------------------------------------------
      #
      # Thin delegates to the ServiceConfiguration concern methods already
      # mixed into AdminSetting — no logic moved, this is just the single
      # call boundary the proxy controllers now go through instead of
      # calling AdminSetting directly (fc-38).

      def proxy_url_config
        AdminSetting.reverse_proxy_url_config
      end

      def update_proxy_url_config!(new_config)
        AdminSetting.update_reverse_proxy_url_config(new_config)
      end

      def validate_proxy_host(host)
        AdminSetting.validate_proxy_host(host)
      end

      def generate_api_url(proxy_context = {})
        AdminSetting.generate_api_url(proxy_context)
      end

      def add_trusted_host(pattern)
        AdminSetting.add_trusted_host(pattern)
      end

      def remove_trusted_host(pattern)
        AdminSetting.remove_trusted_host(pattern)
      end

      def test_proxy_headers(headers)
        AdminSetting.test_proxy_headers(headers)
      end

      # -- Redis / Vault secrets ---------------------------------------------
      #
      # redis_config's "password" and vault_config's "vault_role_id"/
      # "vault_secret_id" used to be stored PLAINTEXT inside their AdminSetting
      # JSON blobs (fc-38 decision #3). They are now separate
      # CredentialEncryptionService-encrypted rows, same mechanism as email's
      # smtp_password_encrypted etc — see
      # db/migrate/20260925020000_encrypt_plaintext_redis_and_vault_admin_settings.rb
      # for the one-time move of already-stored plaintext.
      #
      # Every caller that needs the REAL Redis/Vault credential (config/
      # initializers/redis.rb's actual connection, Security::VaultClient's
      # actual authentication, and the admin UI's connectivity-test actions)
      # must go through these — none of them may read AdminSetting.redis_config
      # or AdminSetting.get("vault_config") directly, or they would silently
      # get a config with no password/credentials once the blob no longer
      # carries them.

      # The non-secret redis fields (host/port/etc, from the
      # ServiceConfiguration concern) plus the real decrypted password.
      def redis_config
        config = AdminSetting.redis_config
        encrypted = AdminSetting.find_by(key: "redis_config_password_encrypted")
        config.merge("password" => encrypted ? decrypt_secret(encrypted.value) : config["password"])
      end

      # `new_config`'s "password" key (if PRESENT — even blank, meaning
      # "clear it") is encrypted into its own row and never reaches the
      # non-secret blob AdminSetting.update_redis_config writes. A masked
      # resubmission ("••••••••") must be stripped by the caller BEFORE this
      # (InfrastructureConfigActions#update_infrastructure_config already
      # does, unchanged) — this method has no way to tell a real password
      # from a mask.
      def update_redis_config!(new_config)
        config_hash = new_config.to_h.stringify_keys
        if config_hash.key?("password")
          password = config_hash.delete("password")
          AdminSetting.set("redis_config_password_encrypted", encrypt_secret(password))
        end
        AdminSetting.update_redis_config(config_hash)
      end

      # vault_addr (non-secret) plus the real decrypted vault_role_id/
      # vault_secret_id.
      def vault_config
        blob = raw_vault_blob
        {
          "vault_addr" => blob["vault_addr"],
          "vault_role_id" => decrypt_secret(AdminSetting.get("vault_role_id_encrypted", "")),
          "vault_secret_id" => decrypt_secret(AdminSetting.get("vault_secret_id_encrypted", ""))
        }
      end

      # `updates` may carry any subset of vault_addr/vault_role_id/
      # vault_secret_id; only keys actually PRESENT are written (the caller —
      # InfrastructureConfigActions#update_vault_config — already filters out
      # blank/masked resubmissions before calling this).
      def update_vault_config!(updates)
        if updates.key?("vault_addr")
          blob = raw_vault_blob
          AdminSetting.set("vault_config", blob.merge("vault_addr" => updates["vault_addr"]).to_json)
        end
        AdminSetting.set("vault_role_id_encrypted", encrypt_secret(updates["vault_role_id"])) if updates.key?("vault_role_id")
        AdminSetting.set("vault_secret_id_encrypted", encrypt_secret(updates["vault_secret_id"])) if updates.key?("vault_secret_id")
      end

      private

      def typed_boolean(key, default:)
        setting = AdminSetting.find_by(key: key)
        return default unless setting

        parse_boolean_string(setting.value, default: default)
      rescue StandardError
        default
      end

      def parse_boolean_string(value, default:)
        value_str = value.to_s.downcase.strip

        return false if FALSE_STRINGS.include?(value_str)
        return true if TRUE_STRINGS.include?(value_str)

        default
      end

      def non_scalar?(value)
        value.is_a?(Hash) || value.is_a?(Array)
      end

      def raw_vault_blob
        raw = AdminSetting.get("vault_config")
        case raw
        when Hash then raw
        when String then raw.present? ? JSON.parse(raw) : {}
        else {}
        end
      rescue JSON::ParserError
        {}
      end
    end
  end
end
