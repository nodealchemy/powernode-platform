# frozen_string_literal: true

module Ai
  class ProviderCredential < ApplicationRecord
    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Associations
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"
    belongs_to :account


    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :encrypted_credentials, presence: true
    validates :encryption_key_id, presence: true
    validate :only_one_default_per_provider
    validate :credentials_format
    validate :expiration_date_future

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :default, -> { where(is_default: true) }
    scope :non_default, -> { where(is_default: false) }
    scope :for_provider, ->(provider) { where(ai_provider_id: provider.is_a?(Ai::Provider) ? provider.id : provider) }
    scope :expires_soon, ->(days = 30) { where("expires_at IS NOT NULL AND expires_at <= ?", days.days.from_now) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :healthy, -> { where(consecutive_failures: 0..2) }
    scope :unhealthy, -> { where("consecutive_failures > 2") }
    scope :recently_used, ->(days = 7) { where("last_used_at >= ?", days.days.ago) }

    # Callbacks
    before_save :ensure_single_default
    before_destroy :prevent_destroy_if_default_and_only
    after_create :set_as_default_if_first

    # Methods
    def credentials
      @credentials ||= decrypt_credentials
    end

    def credentials=(new_credentials)
      @credentials = new_credentials
      self.encrypted_credentials = encrypt_credentials(new_credentials)
      self.encryption_key_id = current_encryption_key_id
    end

    def decrypt
      decrypt_credentials
    end

    def decrypted_api_key
      credentials["api_key"] || credentials[:api_key]
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def expires_soon?(days = 30)
      expires_at.present? && expires_at <= days.days.from_now
    end

    def healthy?
      is_active? && !expired? && consecutive_failures <= 2
    end

    def record_success!
      increment!(:success_count)
      update!(
        last_used_at: Time.current,
        last_test_at: Time.current,
        last_test_status: "success",
        consecutive_failures: 0,
        last_error: nil,
        is_active: true
      )
    end

    def record_failure!(error_message = nil)
      increment!(:consecutive_failures)
      increment!(:failure_count)
      update_columns(
        last_test_at: Time.current,
        last_test_status: "failed",
        last_error: error_message&.truncate(1000),
        is_active: consecutive_failures <= 5  # Auto-disable after 5 failures
      )
    end

    def test_connection
      return false unless healthy?

      begin
        # This would be implemented by the AI provider service
        Ai::ProviderTestService.new(self).test_connection
      rescue StandardError => e
        record_failure!(e.message)
        false
      end
    end

    def usage_summary(period = 30.days)
      {
        period_start: period.ago,
        period_end: Time.current,
        execution_count: execution_count_for_period(period),
        success_rate: success_rate_for_period(period),
        average_cost: average_cost_for_period(period),
        total_tokens: total_tokens_for_period(period)
      }
    end

    def can_be_used?
      is_active? && !expired? && consecutive_failures <= 5
    end

    def make_default!
      transaction do
        # Remove default from other credentials for this provider
        account.ai_provider_credentials
               .where(ai_provider_id: ai_provider_id, is_default: true)
               .where.not(id: id)
               .update_all(is_default: false)

        update!(is_default: true, is_active: true)
      end
    end

    private

    def decrypt_credentials
      return {} unless encrypted_credentials.present?

      # In test environment, use simple base64 decoding
      if Rails.env.test?
        JSON.parse(Base64.strict_decode64(encrypted_credentials))
      else
        Ai::CredentialEncryptionService.decrypt(
          encrypted_credentials,
          encryption_key_id
        )
      end
    rescue StandardError => e
      Rails.logger.error "Failed to decrypt AI credentials: #{e.message}"
      {}
    end

    def encrypt_credentials(credentials_hash)
      return nil unless credentials_hash.present?

      # In test environment, use simple base64 encoding
      if Rails.env.test?
        Base64.strict_encode64(credentials_hash.to_json)
      else
        Ai::CredentialEncryptionService.encrypt(credentials_hash)
      end
    end

    def current_encryption_key_id
      Rails.env.test? ? "test_key" : Ai::CredentialEncryptionService.current_key_id
    end

    def credentials_format
      return unless @credentials.present?

      unless @credentials.is_a?(Hash)
        errors.add(:credentials, "must be a hash")
        return
      end

      # Validate required fields based on provider type
      case provider&.provider_type
      when "openai"
        validate_openai_configuration
      when "anthropic"
        validate_anthropic_configuration
      when "custom"
        validate_custom_configuration
      else
        validate_generic_configuration
      end
    end

    def validate_openai_configuration
      required_fields = %w[api_key]
      optional_fields = %w[organization model]

      validate_required_fields(required_fields)
      validate_field_formats(optional_fields)
    end

    def validate_anthropic_configuration
      required_fields = %w[api_key]
      optional_fields = %w[model]

      validate_required_fields(required_fields)
      validate_field_formats(optional_fields)
    end

    def validate_custom_configuration
      # Custom providers are flexible - require either api_key or base_url
      # This allows different custom provider configurations to work
      validate_generic_configuration
    end

    def validate_generic_configuration
      # At minimum, require either api_key or base_url
      unless @credentials.key?("api_key") || @credentials.key?("base_url")
        errors.add(:credentials, "must include either api_key or base_url")
      end
    end

    def validate_required_fields(fields)
      fields.each do |field|
        unless @credentials[field].present? || @credentials[field.to_sym].present?
          errors.add(:credentials, "must include #{field}")
        end
      end
    end

    def validate_field_formats(optional_fields)
      # Additional format validation can be added here
      if @credentials["api_key"].present? && @credentials["api_key"].length < 10
        errors.add(:credentials, "api_key appears to be too short")
      end

      if @credentials["base_url"].present? && !@credentials["base_url"].match(/\Ahttps?:\/\//)
        errors.add(:credentials, "base_url must be a valid HTTP/HTTPS URL")
      end
    end

    def expiration_date_future
      return unless expires_at.present?

      if expires_at <= Time.current
        errors.add(:expires_at, "must be in the future")
      end
    end

    def ensure_single_default
      return unless is_default_changed? && is_default?

      # Remove default from other credentials for this provider
      Ai::ProviderCredential.where(
        account: account,
        ai_provider_id: ai_provider_id,
        is_default: true
      ).where.not(id: id).update_all(is_default: false)
    end

    def prevent_destroy_if_default_and_only
      if is_default? && account.ai_provider_credentials.for_provider(provider).count == 1
        errors.add(:base, "Cannot delete the only credential for this provider")
        throw :abort
      end
    end

    def set_as_default_if_first
      return if account.ai_provider_credentials.for_provider(provider).count > 1

      update_column(:is_default, true)
    end

    def execution_count_for_period(period)
      provider.agent_executions
              .joins(:provider_credential)
              .where(ai_provider_credentials: { id: id })
              .where("ai_agent_executions.created_at >= ?", period.ago)
              .count
    end

    def success_rate_for_period(period)
      executions = provider.agent_executions
                           .joins(:provider_credential)
                           .where(ai_provider_credentials: { id: id })
                           .where("ai_agent_executions.created_at >= ?", period.ago)

      return 0 if executions.count.zero?

      successful = executions.where(status: "completed").count
      (successful.to_f / executions.count * 100).round(2)
    end

    def average_cost_for_period(period)
      provider.agent_executions
              .joins(:provider_credential)
              .where(ai_provider_credentials: { id: id })
              .where("ai_agent_executions.created_at >= ?", period.ago)
              .average(:cost_usd) || 0.0
    end

    def total_tokens_for_period(period)
      provider.agent_executions
              .joins(:provider_credential)
              .where(ai_provider_credentials: { id: id })
              .where("ai_agent_executions.created_at >= ?", period.ago)
              .sum(:tokens_used) || 0
    end

    def only_one_default_per_provider
      return unless is_default?

      existing = Ai::ProviderCredential.where(
        account_id: account_id,
        ai_provider_id: ai_provider_id,
        is_default: true
      ).where.not(id: id)

      if existing.exists?
        errors.add(:is_default, "can only have one default credential per provider")
      end
    end
  end
end
