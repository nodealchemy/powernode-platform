# frozen_string_literal: true

# ActiveRecord Encryption Configuration
# Encryption keys are required in all environments because models use `encrypts` declarations
Rails.application.configure do
  # Use credentials if available, otherwise use fallback keys (for development/test)
  config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] || Rails.application.credentials.dig(:active_record_encryption, :primary_key) || (Rails.env.local? ? "mHKA6Hni3W6tRlGEdmCgs9uS9q4yPWi2" : raise("ActiveRecord encryption primary_key not configured"))
  config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] || Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) || (Rails.env.local? ? "EikFNeuXUdH8iPXJwatYeLzbu3v9kgN5" : raise("ActiveRecord encryption deterministic_key not configured"))
  config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] || Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) || (Rails.env.local? ? "fwpUiks80xeR4dolB6CsGbkUWnkrluwZ" : raise("ActiveRecord encryption key_derivation_salt not configured"))

  # Additional encryption settings
  config.active_record.encryption.support_unencrypted_data = true
  config.active_record.encryption.extend_queries = true
end

Rails.logger.info "ActiveRecord Encryption configured" if defined?(Rails.logger)
