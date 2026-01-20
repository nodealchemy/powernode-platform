# frozen_string_literal: true

module Ai
  class Provider < ApplicationRecord
    # Authentication
    # No authentication needed for provider definitions

    # Concerns
    include Auditable
    include Ai::Provider::HealthCheckable
    include Ai::Provider::UsageTrackable
    include Ai::Provider::RateLimitable
    include Ai::Provider::ModelManagement
    include Ai::Provider::Configurable
    include Ai::Provider::ProviderSetup
    include Ai::Provider::DevopsIntegration

    # Associations
    belongs_to :account
    has_many :provider_credentials, class_name: "Ai::ProviderCredential", foreign_key: "ai_provider_id", dependent: :destroy
    has_many :credentials, -> { where(is_active: true) }, class_name: "Ai::ProviderCredential", foreign_key: "ai_provider_id", dependent: :destroy
    has_many :agents, class_name: "Ai::Agent", foreign_key: "ai_provider_id", dependent: :nullify
    has_many :agent_executions, class_name: "Ai::AgentExecution", foreign_key: "ai_provider_id", dependent: :restrict_with_error
    has_many :conversations, class_name: "Ai::Conversation", foreign_key: "ai_provider_id", dependent: :restrict_with_error


    # Validations
    validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }
    validates :slug, presence: true, uniqueness: true, length: { maximum: 50 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
    validates :provider_type, presence: true, inclusion: {
      in: %w[openai anthropic google azure huggingface custom ollama local api_gateway],
      message: "is not included in the list"
    }
    validates :api_base_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
    validates :api_endpoint, presence: true
    validate :api_endpoint_must_be_valid_url
    validates :capabilities, presence: true
    validate :capabilities_must_be_meaningful
    validates :supported_models, presence: true
    validates :priority_order, numericality: { greater_than: 0 }
    validates :configuration_schema, presence: true, allow_blank: false

    # Virtual attribute for tests to set default status
    attr_accessor :is_default

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :by_type, ->(type) { where(provider_type: type) }
    scope :supporting_capability, ->(capability) { where("capabilities @> ?", [capability].to_json) }
    scope :ordered_by_priority, -> { order(:priority_order, :name) }
    scope :with_streaming, -> { where(supports_streaming: true) }
    scope :with_functions, -> { where(supports_functions: true) }
    scope :with_vision, -> { where(supports_vision: true) }
    scope :with_code_execution, -> { where(supports_code_execution: true) }
    scope :for_account, ->(account) { where(account: account) }
    scope :default, -> { where(priority_order: 1) }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && slug.blank? }
    before_validation :normalize_capabilities
    before_validation :normalize_provider_type
    before_validation :normalize_api_endpoint

    # Instance Methods
    def supports_capability?(capability)
      capabilities.include?(capability.to_s)
    end

    def to_param
      slug
    end

    def is_default?
      # Check virtual attribute first (including explicit false)
      return @is_default if @is_default == true || @is_default == false
      # This could be enhanced to check per-account defaults
      priority_order == 1
    end

    def is_default=(value)
      @is_default = value

      # Persist the default status in metadata for class method queries
      current_metadata = metadata || {}
      current_metadata["is_default"] = (value == true || value == "true" || value == 1)
      self.metadata = current_metadata

      # Update priority_order based on is_default value
      self.priority_order = 1 if value == true || value == "true" || value == 1
    end

    def provider_summary
      {
        id: id,
        name: name,
        slug: slug,
        provider_type: provider_type,
        is_active: is_active,
        is_default: is_default?,
        health_status: health_status,
        available_models: available_models_list,
        usage_statistics: usage_statistics,
        capabilities: capabilities,
        requires_auth: requires_auth,
        supports_streaming: supports_streaming,
        supports_functions: supports_functions,
        supports_vision: supports_vision,
        supports_code_execution: supports_code_execution
      }
    end

    # Class Methods
    def self.default_for_account(account = nil)
      return nil unless account

      providers = where(account: account).active
      providers.find do |provider|
        provider.metadata&.dig("is_default") == true
      end
    end

    def self.with_healthy_status
      all.select do |provider|
        if provider.instance_variable_get(:@health_status_override)
          provider.instance_variable_get(:@health_status_override) == "healthy"
        else
          provider.healthy?
        end
      end
    end

    private

    def update_metadata(key, value)
      current_metadata = metadata || {}
      current_metadata[key] = value
      update!(metadata: current_metadata)
    end

    def api_endpoint_must_be_valid_url
      return if api_endpoint.blank?

      begin
        uri = URI.parse(api_endpoint)
        unless %w[http https].include?(uri.scheme)
          errors.add(:api_endpoint, "is invalid")
          return
        end

        if uri.host.blank?
          errors.add(:api_endpoint, "is invalid")
          return
        end

        if api_endpoint == "http://" || api_endpoint == "https://" || api_endpoint.end_with?("://")
          errors.add(:api_endpoint, "is invalid")
          nil
        end
      rescue URI::InvalidURIError
        errors.add(:api_endpoint, "is invalid")
      end
    end

    def capabilities_must_be_meaningful
      return unless capabilities.is_a?(Array)

      known_capabilities = %w[
        text_generation chat conversation reasoning analysis
        code_generation creative_writing structured_output function_calling
        document_analysis image_generation image_analysis vision code_execution
        text_embedding code_embedding audio_generation audio_transcription
        video_generation video_analysis translation summarization
        search retrieval fine_tuning model_training devops_execution
      ]

      unknown_capabilities = capabilities - known_capabilities
      if unknown_capabilities.any?
        errors.add(:capabilities, "contains unknown capabilities: #{unknown_capabilities.join(', ')}")
      end

      if capabilities.empty?
        errors.add(:capabilities, "must include at least one capability")
      end
    end

    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-").strip
      self.slug = ensure_unique_slug(base_slug)
    end

    def ensure_unique_slug(base_slug)
      slug_candidate = base_slug
      counter = 1

      while Ai::Provider.where(slug: slug_candidate).where.not(id: id).exists?
        slug_candidate = "#{base_slug}-#{counter}"
        counter += 1
      end

      slug_candidate
    end

    def normalize_capabilities
      return unless capabilities.is_a?(Array)

      self.capabilities = capabilities.map(&:to_s).uniq.compact
    end

    def normalize_provider_type
      return unless provider_type.present?

      self.provider_type = provider_type.to_s.strip.downcase
    end

    def normalize_api_endpoint
      return unless api_endpoint.present?

      self.api_endpoint = api_endpoint.to_s.strip
    end
  end
end
