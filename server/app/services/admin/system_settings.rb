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
  #   - Rate limiting's dotted "rate_limiting.*" keys — read through a
  #     dedicated accessor added alongside the key-mismatch fix, not here.
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

    class << self
      # -- General ------------------------------------------------------------

      # Raw string values (nil when unset) for the flat keys in GENERAL_KEYS.
      def general_settings
        GENERAL_KEYS.index_with { |key| AdminSetting.find_by(key: key)&.value }
      end

      # Mirrors AdminSettingsController#update's pre-move writer exactly: a
      # flat key writes its `.to_s` directly; a Hash value (system_notifications,
      # rate_limiting, feature_flags) fans out to "key.sub_key" rows. Returns
      # the flat map of what was written (original, un-stringified values),
      # the same shape the controller already renders back to the caller.
      def update_general_settings!(settings_params)
        updated = {}

        settings_params.each do |key, value|
          if value.is_a?(Hash)
            value.each do |sub_key, sub_value|
              setting_key = "#{key}.#{sub_key}"
              AdminSetting.find_or_initialize_by(key: setting_key).update!(value: sub_value.to_s)
              updated[setting_key] = sub_value
            end
          else
            AdminSetting.find_or_initialize_by(key: key.to_s).update!(value: value.to_s)
            updated[key] = value
          end
        end

        updated
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

      private

      def typed_boolean(key, default:)
        setting = AdminSetting.find_by(key: key)
        return default unless setting

        value_str = setting.value.to_s.downcase.strip

        return false if FALSE_STRINGS.include?(value_str)
        return true if TRUE_STRINGS.include?(value_str)

        default
      rescue StandardError
        default
      end
    end
  end
end
