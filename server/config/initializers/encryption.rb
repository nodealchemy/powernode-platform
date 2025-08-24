# frozen_string_literal: true

# ActiveRecord Encryption Configuration
Rails.application.configure do
  # Only configure encryption if we're not in test mode or if explicitly enabled
  unless Rails.env.test? && ENV['ENABLE_ENCRYPTION'] != 'true'
    config.active_record.encryption.primary_key = Rails.application.credentials.dig(:active_record_encryption, :primary_key) || 'mHKA6Hni3W6tRlGEdmCgs9uS9q4yPWi2'
    config.active_record.encryption.deterministic_key = Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) || 'EikFNeuXUdH8iPXJwatYeLzbu3v9kgN5'
    config.active_record.encryption.key_derivation_salt = Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) || 'fwpUiks80xeR4dolB6CsGbkUWnkrluwZ'
    
    # Additional encryption settings
    config.active_record.encryption.support_unencrypted_data = true
    config.active_record.encryption.extend_queries = true
  end
end

Rails.logger.info "ActiveRecord Encryption configured" if defined?(Rails.logger)