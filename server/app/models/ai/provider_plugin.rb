# frozen_string_literal: true

# AI Provider Plugin Model
# Specific configuration for AI provider type plugins
module Ai
  class ProviderPlugin < ApplicationRecord
    # Associations
    belongs_to :plugin

    # Validations
    validates :provider_type, presence: true,
              inclusion: { in: %w[openai_compatible anthropic_compatible custom] }
    validates :plugin_id, uniqueness: true

    # JSON attributes
    attribute :supported_capabilities, :json, default: -> { [] }
    attribute :models, :json, default: -> { [] }
    attribute :authentication_schema, :json, default: -> { {} }
    attribute :default_configuration, :json, default: -> { {} }

    # Scopes
    scope :by_provider_type, ->(type) { where(provider_type: type) }
    scope :with_capability, ->(capability) {
      where("supported_capabilities @> ?", [capability].to_json)
    }

    # Model accessors
    def model_ids
      models.map { |m| m["id"] }
    end

    def model_by_id(model_id)
      models.find { |m| m["id"] == model_id }
    end

    def supports_capability?(capability)
      supported_capabilities.include?(capability.to_s)
    end

    # Authentication field helpers
    def authentication_fields
      authentication_schema["fields"] || []
    end

    def required_authentication_fields
      authentication_fields.select { |f| f["required"] }
    end
  end
end
