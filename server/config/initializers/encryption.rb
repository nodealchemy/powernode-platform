# frozen_string_literal: true

# ActiveRecord Encryption Configuration
#
# Rails 8.1.3 changed encryption key resolution: the railtie now calls
# ActiveRecord::Encryption.configure() with credentials as named kwargs,
# which override any keys set via config.active_record.encryption.*.
# We hook into the same on_load lifecycle to run AFTER the railtie and
# call configure() directly with the resolved keys.
ActiveSupport.on_load(:active_record_encryption) do
  resolve_key = ->(env_var, credential_path, fallback) {
    ENV[env_var] ||
      Rails.application.credentials.dig(*credential_path) ||
      (Rails.env.local? ? fallback : raise("ActiveRecord encryption #{credential_path.last} not configured"))
  }

  ActiveRecord::Encryption.configure(
    primary_key: resolve_key.call(
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
      %i[active_record_encryption primary_key],
      "mHKA6Hni3W6tRlGEdmCgs9uS9q4yPWi2"
    ),
    deterministic_key: resolve_key.call(
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
      %i[active_record_encryption deterministic_key],
      "EikFNeuXUdH8iPXJwatYeLzbu3v9kgN5"
    ),
    key_derivation_salt: resolve_key.call(
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",
      %i[active_record_encryption key_derivation_salt],
      "fwpUiks80xeR4dolB6CsGbkUWnkrluwZ"
    ),
    support_unencrypted_data: true,
    extend_queries: true
  )

  Rails.logger.info "ActiveRecord Encryption configured" if defined?(Rails.logger)
end
