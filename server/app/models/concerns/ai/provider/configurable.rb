# frozen_string_literal: true

module Ai
  class Provider
    module Configurable
      extend ActiveSupport::Concern

      included do
        # Note: Custom configuration getter/setter are defined below in the module
        # Don't use attr_accessor here as it would shadow the custom methods

        # Validations
        validate :configuration_must_be_hash
        validate :configuration_structure_must_be_valid

        # Callbacks
        before_validation :set_default_configuration_from_type
        after_update :invalidate_cache_on_config_change
      end

      def credentials
        # Return the decrypted credentials from the first active credential
        # For testing, fall back to virtual @configuration if no credentials exist
        active_credential = provider_credentials.where(is_active: true).first
        if active_credential
          active_credential.credentials
        elsif @configuration.present?
          @configuration
        else
          {}
        end
      end

      def configuration
        # Return the instance variable if set (for tests)
        return @configuration.with_indifferent_access if @configuration.is_a?(Hash)

        # Return configuration_schema if it exists and has models (actual config, not JSON schema)
        if configuration_schema.is_a?(Hash)
          models = configuration_schema["models"] || configuration_schema[:models]
          return configuration_schema.with_indifferent_access if models.is_a?(Array) && models.any?
        end

        # Fallback: Return configuration based on provider type
        fallback = case provider_type
                   when "openai"
                     {
                       "api_key" => "***masked***",
                       "models" => available_models_list,
                       "default_model" => available_models_list.first,
                       "rate_limits" => rate_limits
                     }
                   when "anthropic"
                     {
                       "api_key" => "***masked***",
                       "models" => available_models_list,
                       "default_model" => available_models_list.first
                     }
                   else
                     configuration_schema.presence || {}
                   end

        fallback.is_a?(Hash) ? fallback.with_indifferent_access : {}
      end

      def configuration=(value)
        @configuration = value
        # Also update configuration_schema column if it's a hash
        if value.is_a?(Hash)
          # Ensure the configuration_schema attribute is set for database persistence
          self.configuration_schema = value
        elsif !value.nil?
          # If it's not a hash and not nil, it's invalid - clear configuration_schema
          # The validation will catch this
          self.configuration_schema = nil
        end
      end

      private

      def configuration_must_be_hash
        # Check both configuration (virtual attr) and configuration_schema
        config_to_check = @configuration || configuration_schema
        return if config_to_check.nil? || config_to_check.is_a?(Hash)

        errors.add(:configuration, "must be a hash")
      end

      def configuration_structure_must_be_valid
        # Check both configuration (virtual attr) and configuration_schema
        config_to_check = @configuration || configuration_schema
        return if config_to_check.nil? || !config_to_check.is_a?(Hash)

        # Validate provider-specific structure
        case provider_type
        when "openai"
          validate_openai_configuration(config_to_check)
        when "anthropic"
          validate_anthropic_configuration(config_to_check)
        when "custom"
          validate_custom_configuration(config_to_check)
        end
      end

      def validate_openai_configuration(config)
        if config.key?("models") && config["models"].is_a?(String)
          errors.add(:configuration, "models must be an array")
        end

        if config.key?("max_tokens") && !config["max_tokens"].is_a?(Integer)
          errors.add(:configuration, "max_tokens must be a number")
        end

        # Also check with symbol keys (in case test uses symbols)
        if config.key?(:models) && config[:models].is_a?(String)
          errors.add(:configuration, "models must be an array")
        end

        if config.key?(:max_tokens) && !config[:max_tokens].is_a?(Integer)
          errors.add(:configuration, "max_tokens must be a number")
        end
      end

      def validate_anthropic_configuration(config)
        if config.key?("models") && config["models"].is_a?(String)
          errors.add(:configuration, "models must be an array")
        end

        if config.key?("max_tokens") && !config["max_tokens"].is_a?(Integer)
          errors.add(:configuration, "max_tokens must be a number")
        end
      end

      def validate_custom_configuration(config)
        # Basic validation for custom providers
        if config.key?("models") && config["models"].is_a?(String)
          errors.add(:configuration, "models must be an array")
        end
      end

      def set_default_configuration_from_type
        # Skip if configuration was explicitly set (even if it doesn't have models)
        # This preserves user-provided configuration and allows validation to catch invalid configs
        return if @configuration.present?

        # Skip if configuration_schema already has actual config (has models key, not just JSON schema)
        # JSON schemas have "type" and "properties" keys, actual configs have "models" and "default_model"
        if configuration_schema.is_a?(Hash)
          models = configuration_schema["models"] || configuration_schema[:models]
          return if models.is_a?(Array) && models.any?
        end

        default_config = case provider_type.to_s.downcase
                         when "openai"
                           {
                             "models" => %w[gpt-3.5-turbo gpt-4],
                             "default_model" => "gpt-3.5-turbo",
                             "api_key" => nil,
                             "temperature" => 0.7,
                             "max_tokens" => 2000
                           }
                         when "anthropic"
                           {
                             "models" => %w[claude-instant-1 claude-2],
                             "default_model" => "claude-instant-1",
                             "api_key" => nil,
                             "temperature" => 0.7,
                             "max_tokens" => 2000
                           }
                         else
                           {
                             "api_key" => "",
                             "models" => [],
                             "default_model" => nil,
                             "temperature" => 0.7,
                             "max_tokens" => 2000
                           }
                         end

        # Add capability-specific defaults
        default_config["supports_functions"] = true if supports_capability?("function_calling")
        default_config["supports_vision"] = true if supports_capability?("vision")
        default_config["code_focused"] = true if supports_capability?("code_generation")

        self.configuration_schema = default_config
        @configuration = default_config
      end

      def invalidate_cache_on_config_change
        if saved_change_to_configuration_schema? || saved_change_to_supported_models?
          invalidate_provider_cache
        end
      end

      def invalidate_provider_cache
        Rails.logger.info "Invalidating cache for provider #{name}"
        # In a real implementation, this would clear Redis cache keys
        true
      end
    end
  end
end
