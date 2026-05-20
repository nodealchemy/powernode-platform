# frozen_string_literal: true

# ActiveRecord Encryption Configuration
#
# Rails 8.1.3 changed encryption key resolution: the railtie now calls
# ActiveRecord::Encryption.configure() with credentials as named kwargs,
# which override any keys set via config.active_record.encryption.*.
# We hook into the same on_load lifecycle to run AFTER the railtie and
# call configure() directly with the resolved keys.
#
# Key rotation: each ACTIVE_RECORD_ENCRYPTION_*_KEY / SALT env var accepts
# a comma-separated list. The first entry is used for new writes; all
# entries are tried for reads. Rotation procedure:
#   1. Generate new keys; set env to "NEW,OLD" (new first, old second).
#   2. Restart backend.
#   3. Run `bin/rails ar_encryption:re_encrypt_all` to re-save every row
#      with `encrypts` declarations under the new primary key.
#   4. Set env back to just "NEW"; restart. Old keys are no longer trusted.
ActiveSupport.on_load(:active_record_encryption) do
  resolve = ->(env_var, credential_path, fallback) {
    raw = ENV[env_var]
    return raw.split(",").map(&:strip).reject(&:empty?).then { |a| a.size == 1 ? a.first : a } if raw && !raw.empty?
    Rails.application.credentials.dig(*credential_path) ||
      (Rails.env.local? ? fallback : raise("ActiveRecord encryption #{credential_path.last} not configured"))
  }

  primary_key         = resolve.call("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
                                      %i[active_record_encryption primary_key],
                                      "mHKA6Hni3W6tRlGEdmCgs9uS9q4yPWi2")
  deterministic_key   = resolve.call("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
                                      %i[active_record_encryption deterministic_key],
                                      "EikFNeuXUdH8iPXJwatYeLzbu3v9kgN5")
  key_derivation_salt = resolve.call("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",
                                      %i[active_record_encryption key_derivation_salt],
                                      "fwpUiks80xeR4dolB6CsGbkUWnkrluwZ")

  ActiveRecord::Encryption.configure(
    primary_key:              primary_key,
    deterministic_key:        deterministic_key,
    key_derivation_salt:      key_derivation_salt,
    support_unencrypted_data: true,
    extend_queries:           true
  )

  if defined?(Rails.logger)
    Rails.logger.info "ActiveRecord Encryption configured"
  end
end
