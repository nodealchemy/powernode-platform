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

      # EMAIL ONLY (fc-38 review item #4). Backward compatibility, preserved
      # from the pre-move controller: a value written before encryption was
      # added was stored as plaintext and cannot be decrypted. Treat it as
      # its literal value so an existing config keeps sending mail until the
      # next save re-encrypts it. redis_config/vault_config never had this
      # legacy case (they moved straight from unencrypted-in-blob to an
      # encrypted key, never plaintext-in-an-_encrypted-key), so they use
      # .decrypt_infrastructure_secret instead, which has no such fallback.
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

      # For redis_config/vault_config ONLY (fc-38 review item #4) — unlike
      # email, neither ever had a pre-encryption legacy row storing plaintext
      # under an "_encrypted" key, so there is no backward-compatible
      # "treat undecryptable ciphertext as the literal value" case to
      # preserve. A decrypt failure here can only mean real corruption or a
      # key-rotation gap, and the ciphertext must never be handed anywhere as
      # if it were the actual credential — returns nil, and logs the FIELD
      # NAME and error CLASS only, never a value (matching every migration's
      # own logging rule in this area).
      def decrypt_infrastructure_secret(encrypted_value, field:)
        return nil if encrypted_value.blank?

        ::Security::CredentialEncryptionService.decrypt_value(encrypted_value).to_s
      rescue ::Security::CredentialEncryptionService::DecryptionError => e
        Rails.logger.error("[Admin::SystemSettings] Failed to decrypt #{field}: #{e.class}")
        nil
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

      # fc-38 review round 3 item #4: a redis:// / rediss:// URL can embed a
      # credential as userinfo (redis://[user]:password@host:port/db) —
      # either the `user:pass@` or the password-only `:pass@` form Redis
      # itself uses. Public (not `private`) because both the controller
      # (write-side rejection, GET-side masking) and this class's own
      # update_redis_config! (blob sanitization) need it.
      #
      # round 4 review: this used to be a hand-rolled regex
      # (`%r{\A(rediss?://)[^/@]*@}i`) matching the userinfo segment as
      # "anything but / or @" — which meant an UNENCODED "/" inside a
      # password made the whole pattern silently fail to match (the
      # character class stops at the "/", never reaches the "@" that
      # follows), so a credentialed URL like "redis://:my/pass@host:6379/0"
      # read as credential-free. URI parsing is authoritative instead of a
      # hand-maintained pattern.
      def url_contains_credentials?(url)
        return false if url.blank?

        URI.parse(url.to_s).userinfo.present?
      rescue URI::InvalidURIError
        # Can't verify an unparseable string is credential-free — fail
        # CLOSED so a request-boundary check rejects it rather than
        # silently accepting something nobody actually validated.
        true
      end

      # fc-38 round 4 RE-review (security, MEDIUM): a URI::InvalidURIError
      # used to fall through to returning the URL UNCHANGED — failing OPEN.
      # Ruby 3.2's RFC2396 URI.parse raises on a credentialed URL whose
      # userinfo contains an unencoded "/", "@", "#", "?" or a literal space
      # (e.g. "redis://:my/pass@host", "redis://:p@ss@host",
      # "redis://:p#w@host", "redis://:p?w@host", "redis://:p w@host") —
      # every one of those is a shape a REAL password can take, and
      # strip_url_credentials is called UNCONDITIONALLY on every
      # infrastructure_config GET/PUT response (never gated by
      # url_contains_credentials? first), so returning it unchanged leaked
      # the plaintext credential straight into the response body, and left
      # it un-sanitized in the blob via sanitize_url_in_blob!.
      #
      # On a parse failure this now REDACTS everything between "scheme://"
      # and the LAST "@" in the string, rather than passing it through.
      # Deliberately `.*@` (matches through whitespace), not `[^\s]*@`
      # (excludes whitespace) — the latter fails to match AT ALL on the
      # literal-space shape above (nothing bridges the space to reach the
      # "@"), which would leave that one shape unredacted. A string with no
      # "@" at all was never credentialed and is left byte-for-byte
      # unchanged — nothing to redact.
      #
      # fc-38 final review: /m so ".*" crosses a newline inside the userinfo,
      # and "\A\s*" so leading whitespace before the scheme can't stop the
      # match — both shapes used to come back unchanged. Anything the pattern
      # still can't handle (an "@" left over, e.g. no scheme at all) returns
      # UNPARSEABLE_URL_REDACTED_PLACEHOLDER — never the input.
      UNPARSEABLE_URL_CREDENTIAL_PATTERN = %r{\A\s*([a-z][a-z0-9+.-]*://).*@}im.freeze
      UNPARSEABLE_URL_REDACTED_PLACEHOLDER = "[redacted: unparseable URL with credentials]"

      # Removes a URL's userinfo (user + password), leaving host/port/path
      # untouched — a URL's host portion isn't secret, only whatever
      # credential was embedded before the "@". Called unconditionally on
      # every infrastructure_config GET/PUT response (not just ones already
      # confirmed credentialed), so this must never raise, and must never
      # leak a credential it can't structurally parse (see the pattern's own
      # comment above) — an already-credential-free URL still comes back
      # byte-for-byte unchanged.
      def strip_url_credentials(url)
        return url if url.blank?

        uri = URI.parse(url.to_s)
        return url unless uri.userinfo.present?

        uri.user = nil
        uri.password = nil
        uri.to_s
      rescue URI::InvalidURIError
        redacted = url.to_s.sub(UNPARSEABLE_URL_CREDENTIAL_PATTERN, '\1')
        redacted.include?("@") ? UNPARSEABLE_URL_REDACTED_PLACEHOLDER : redacted
      end

      # The non-secret redis fields (host/port/etc, from the
      # ServiceConfiguration concern) plus the real decrypted password.
      #
      # fc-38 review round 3 item #2: a decrypt failure returns nil from
      # decrypt_infrastructure_secret — `config.merge("password" => nil)`
      # used to ship that nil straight over config["password"]'s own ENV/
      # blob default, so a corrupted encrypted row sent the real Redis
      # connection out UNAUTHENTICATED rather than falling back to whatever
      # credential was configured before the corruption. `||` instead of an
      # unconditional merge: only a decrypt SUCCESS (even an intentionally
      # blank "") overrides the blob's own value; a nil falls through to it.
      def redis_config
        config = AdminSetting.redis_config
        encrypted = AdminSetting.find_by(key: "redis_config_password_encrypted")
        decrypted = encrypted ? decrypt_infrastructure_secret(encrypted.value, field: "redis_config_password") : nil
        config.merge("password" => decrypted || config["password"])
      end

      # `new_config`'s "password" key (if PRESENT — even blank) is encrypted
      # into its own row and never reaches the non-secret blob
      # AdminSetting.update_redis_config writes. A masked resubmission
      # ("••••••••") must be stripped by the caller BEFORE this
      # (InfrastructureConfigActions#update_infrastructure_config already
      # does, unchanged) — this method has no way to tell a real password
      # from a mask.
      #
      # `clear_password:` (fc-38 review round 3 item #3(b)) is the explicit
      # signal a blank "password" can't be: a blank value here still means
      # "unchanged" (the caller didn't touch this field — see
      # InfrastructureConfigActions#unchanged_secret_value?, which strips a
      # blank/masked "password" key before it ever reaches this method), so
      # there was previously no way to actually REMOVE a saved credential.
      # clear_password: true destroys the encrypted row outright, which
      # .redis_config's decrypt-failure/no-row fallback (review round 3 item
      # #2) then reads through to the ENV/blob default — never a plaintext
      # "" written anywhere.
      #
      # The destroy happens LAST, after AdminSetting.update_redis_config and
      # the strip below, not first — kept this way as defense in depth even
      # though the root cause it originally guarded against (round 3) is now
      # fixed at the source: AdminSetting.update_redis_config used to
      # deep-merge the ENV-merged `redis_config` read into whatever got
      # (transiently) written to the blob, so destroying the encrypted row
      # FIRST let the strip's item #1 backfill see that transient ENV value
      # as "a leftover plaintext with no encrypted row" and re-encrypt it
      # right back in — silently undoing the clear. AdminSetting.
      # update_redis_config now merges into the raw stored blob only (fc-38
      # round 4), so this can no longer happen either way — but destroy-last
      # costs nothing and removes any doubt.
      def update_redis_config!(new_config, clear_password: false)
        config_hash = new_config.to_h.stringify_keys
        if clear_password
          config_hash.delete("password")
        elsif config_hash.key?("password")
          password = config_hash.delete("password")
          AdminSetting.set("redis_config_password_encrypted", encrypt_secret(password))
        end
        AdminSetting.update_redis_config(config_hash)

        # fc-38 review item #3(b), root-caused in round 4: this used to
        # exist because AdminSetting.update_redis_config baked
        # ENV["REDIS_PASSWORD"] into the blob on every write that omitted
        # "password" (fixed at the source now — see
        # ServiceConfiguration#update_redis_config). What's left for this to
        # do is genuine defense in depth: a blob can still carry a plaintext
        # "password" left over from before encryption existed (the one-time
        # migration's job) or from a row this hardening hasn't reached yet —
        # this backfills that into its own encrypted row before stripping it.
        strip_secret_keys_from_blob!("redis_config", "password" => "redis_config_password_encrypted")

        # fc-38 review round 3 item #4, root-caused in round 4: same history
        # as the password strip above — ServiceConfiguration#update_redis_config
        # no longer bakes ENV["REDIS_URL"] into the blob, so this now only
        # ever sanitizes a URL an admin genuinely submitted with embedded
        # credentials (the controller also 422s that at the request
        # boundary; this is the service-layer backstop). Unlike password, a
        # URL isn't wholly secret — only its userinfo portion — so this
        # SANITIZES it in place rather than stripping the whole key.
        sanitize_url_in_blob!("redis_config")

        AdminSetting.find_by(key: "redis_config_password_encrypted")&.destroy if clear_password
      end

      # vault_addr (non-secret) plus the real decrypted vault_role_id/
      # vault_secret_id. Falls back to the blob's own plaintext value when no
      # encrypted row exists yet (fc-38 review item #2) — matching
      # .redis_config's fallback — so a row written before the data
      # migration ran, or before this hardening shipped, doesn't read as a
      # blank credential in the gap.
      def vault_config
        blob = raw_vault_blob
        role_encrypted = AdminSetting.find_by(key: "vault_role_id_encrypted")
        secret_encrypted = AdminSetting.find_by(key: "vault_secret_id_encrypted")

        {
          "vault_addr" => blob["vault_addr"],
          "vault_role_id" => role_encrypted ? decrypt_infrastructure_secret(role_encrypted.value, field: "vault_role_id") : blob["vault_role_id"].to_s,
          "vault_secret_id" => secret_encrypted ? decrypt_infrastructure_secret(secret_encrypted.value, field: "vault_secret_id") : blob["vault_secret_id"].to_s
        }
      end

      # `updates` may carry any subset of vault_addr/vault_role_id/
      # vault_secret_id; only keys actually PRESENT are written (the caller —
      # InfrastructureConfigActions#update_vault_config — already filters out
      # blank/masked resubmissions before calling this).
      #
      # `clear_vault_role_id:`/`clear_vault_secret_id:` (fc-38 review round 3
      # item #3(b)) are the explicit "remove this credential" signal a blank
      # value can't be, for the same reason as redis's clear_password: — a
      # blank vault_role_id/vault_secret_id already means "unchanged" (see
      # InfrastructureConfigActions#unchanged_secret_value?), so there was no
      # way to actually clear one without deleting the encrypted row
      # out-of-band. Destroys the row outright; .vault_config's no-row
      # fallback then reads through to the blob's own (empty) value.
      #
      # As with redis's clear_password:, both clear destroys happen LAST —
      # after the vault_addr merge and the strip below, not before — for the
      # same ordering reason: destroying first and then letting the strip's
      # item #1 backfill see a leftover blob value with no encrypted row
      # would re-encrypt it right back in.
      def update_vault_config!(updates, clear_vault_role_id: false, clear_vault_secret_id: false)
        if updates.key?("vault_addr")
          blob = raw_vault_blob
          AdminSetting.set("vault_config", blob.merge("vault_addr" => updates["vault_addr"]).to_json)
        end

        AdminSetting.set("vault_role_id_encrypted", encrypt_secret(updates["vault_role_id"])) if !clear_vault_role_id && updates.key?("vault_role_id")
        AdminSetting.set("vault_secret_id_encrypted", encrypt_secret(updates["vault_secret_id"])) if !clear_vault_secret_id && updates.key?("vault_secret_id")

        # fc-38 review item #3(b): the vault_addr-only branch above merges
        # `raw_vault_blob` (whatever the blob currently holds) with the new
        # vault_addr — a pre-existing plaintext vault_role_id/vault_secret_id
        # in that blob (a leftover from before this hardening shipped, or a
        # row the migration hasn't reached) would otherwise round-trip
        # straight back into the blob on every subsequent vault_addr-only
        # save, keeping the plaintext alive indefinitely.
        strip_secret_keys_from_blob!("vault_config", "vault_role_id" => "vault_role_id_encrypted", "vault_secret_id" => "vault_secret_id_encrypted")

        AdminSetting.find_by(key: "vault_role_id_encrypted")&.destroy if clear_vault_role_id
        AdminSetting.find_by(key: "vault_secret_id_encrypted")&.destroy if clear_vault_secret_id
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

      # Removes each key of `field_to_encrypted_key` from the `blob_key`
      # AdminSetting row's JSON value, if present — called after every write
      # to redis_config/vault_config (fc-38 review item #3(b)) so a secret
      # field re-merged in by another code path (a stale/legacy blob) never
      # survives a save. A no-op when the row doesn't exist, isn't valid
      # JSON, or already carries none of the fields.
      #
      # redis's ENV-defaults route into this (ServiceConfiguration#
      # update_redis_config deep-merging the ENV-merged read back into the
      # blob) is closed at the source now (fc-38 round 4) — see that
      # method's doc comment — so this no longer sees a freshly ENV-baked
      # value on an ordinary save, only genuine leftovers.
      #
      # fc-38 review round 3 item #1 (MEDIUM): stripping used to be
      # unconditional — a plaintext field found in the blob was simply
      # deleted, with no check for whether its `_encrypted` row already
      # existed. A host-only redis save (or vault_addr-only save) against a
      # row from BEFORE the encryption migration ran (or before this
      # hardening shipped) stripped the plaintext into the void: no
      # encrypted row was ever created, so the credential was permanently
      # lost, not migrated. Now: for each field present in the blob whose
      # encrypted row is still missing, encrypt it into that row FIRST —
      # same logic as the one-time migration — then strip the blob, all
      # inside one transaction so a save is never left half-done (encrypted
      # written but blob not yet stripped, or vice versa).
      def strip_secret_keys_from_blob!(blob_key, field_to_encrypted_key)
        setting = AdminSetting.find_by(key: blob_key)
        return unless setting

        blob = JSON.parse(setting.value)
        return unless blob.is_a?(Hash)
        return unless field_to_encrypted_key.keys.any? { |field| blob.key?(field) }

        ActiveRecord::Base.transaction do
          field_to_encrypted_key.each do |field, encrypted_key|
            next unless blob.key?(field)

            value = blob[field]
            AdminSetting.create!(key: encrypted_key, value: encrypt_secret(value)) if value.present? && !AdminSetting.exists?(key: encrypted_key)
            blob.delete(field)
          end
          setting.update!(value: blob.to_json)
        end
      rescue JSON::ParserError
        nil
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

      # Rewrites the `blob_key` row's "url" in place, stripped of any
      # embedded credential — called after every redis_config write (fc-38
      # review round 3 item #4; root-caused in round 4, see
      # ServiceConfiguration#update_redis_config). Now purely defense in
      # depth for a URL an admin genuinely submitted with embedded
      # credentials — the write path no longer bakes ENV["REDIS_URL"] into
      # the blob, so there is nothing ENV-derived left for this to sanitize.
      # A no-op when the row doesn't exist, isn't valid JSON, or its "url"
      # already has no credentials.
      def sanitize_url_in_blob!(blob_key)
        setting = AdminSetting.find_by(key: blob_key)
        return unless setting

        blob = JSON.parse(setting.value)
        return unless blob.is_a?(Hash) && url_contains_credentials?(blob["url"])

        blob["url"] = strip_url_credentials(blob["url"])
        setting.update!(value: blob.to_json)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
