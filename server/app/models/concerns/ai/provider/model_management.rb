# frozen_string_literal: true

module Ai
  class Provider
    module ModelManagement
      extend ActiveSupport::Concern

      included do
        # Callbacks
        before_validation :normalize_supported_models
      end

      def supports_model?(model_name)
        return false if model_name.blank?

        # Use available_models (which considers configuration) and handle case insensitive matching
        available_models.any? { |model| model.to_s.downcase == model_name.to_s.downcase }
      end

      def get_model_info(model_name)
        supported_models.find { |model| model["name"] == model_name || model["id"] == model_name }
      end

      def available_models_for_account(account)
        # Filter models based on account's subscription or permissions
        # This can be enhanced based on business logic
        supported_models
      end

      def available_models
        # First check if models are configured in the configuration field (handle both symbol and string keys)
        if @configuration.is_a?(Hash)
          models = @configuration[:models] || @configuration["models"]
          return models if models&.any?
        end

        # Then try to fetch from API
        begin
          api_models = fetch_models_from_api
          return api_models if api_models&.any?
        rescue NoMethodError
          # Method might not be implemented in all providers
        end

        # Finally, extract model IDs from supported_models (prefer API identifier over display name)
        if supported_models&.any?
          return supported_models.map { |model| model["id"] || model["name"] }.compact
        end

        []
      end

      def available_models_list
        supported_models.map { |model| model.is_a?(Hash) ? model["name"] || model["id"] : model }
      end

      def default_model
        # Check virtual @configuration first (for tests), then configuration_schema
        if @configuration.is_a?(Hash)
          default = @configuration[:default_model] || @configuration["default_model"]
          return default if default.present?
        end

        # Fall back to configuration_schema or available models
        config_default = configuration_schema&.dig("default_model") if configuration_schema.is_a?(Hash)
        config_default || available_models.first
      end

      def default_parameters_for_model(model_name)
        model_info = get_model_info(model_name)
        return default_parameters unless model_info

        default_parameters.merge(model_info["default_parameters"] || {})
      end

      def model_capabilities(model_name)
        return nil if model_name.blank?

        # Check virtual @configuration first (for tests)
        if @configuration.is_a?(Hash) && @configuration[:model_capabilities].is_a?(Hash)
          capabilities = @configuration[:model_capabilities][model_name.to_s] || @configuration[:model_capabilities][model_name.to_sym]
          return capabilities.with_indifferent_access if capabilities
        end

        # Fall back to supported_models info
        model_info = get_model_info(model_name)
        model_info&.dig("capabilities") || model_info&.dig("features")
      end

      private

      def normalize_supported_models
        return unless supported_models.is_a?(Array)

        self.supported_models = supported_models.map do |model|
          if model.is_a?(String)
            { "name" => model, "id" => model }
          else
            model
          end
        end
      end

      def fetch_models_from_api
        # In a real implementation, this would make API calls to fetch available models
        Rails.logger.info "Fetching models from API for provider #{name}"

        # Instead of hardcoding by type, return empty to force use of supported_models
        # This makes providers capability-driven rather than type-driven
        []
      end
    end
  end
end
