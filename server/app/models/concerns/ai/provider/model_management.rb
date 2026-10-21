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

        # Finally, extract model IDs from supported_models (prefer API identifier
        # over display name). Ai::ModelTiers.id_for reads a Hash's "id"/"name"
        # AND a bare String entry — `model["id"]` on a String is String#[], which
        # returned nil for any id not containing "id", so a string catalog used
        # to vanish here and the default rule below could not see it (E3b).
        if supported_models&.any?
          return supported_models.filter_map { |model| ::Ai::ModelTiers.id_for(model).presence }
        end

        []
      end

      def available_models_list
        supported_models.map { |model| model.is_a?(Hash) ? model["name"] || model["id"] : model }
      end

      # The model an unpinned caller gets (campaign 01a08c9b, E3b ruling).
      #
      # An operator's explicit, NON-BLANK default wins. Otherwise: the
      # LIGHTEST-tier model the provider's synced catalog lists, ties broken by
      # catalog order. Never a literal — an empty catalog has no default, and
      # every resolver then refuses with no_model_configured instead of guessing.
      #
      # Why not the first catalog entry: sync ORDERS catalogs most-capable-first
      # (Sync::Anthropic#anthropic_model_sort_priority, Sync::OpenAI's
      # openai_model_priority), so "first" would silently make every unpinned
      # default the priciest model on the account. The literals this replaced
      # were each type's cheap model; the tier rule keeps that intent without
      # naming one.
      def default_model
        configured = (@configuration[:default_model] || @configuration["default_model"]) if @configuration.is_a?(Hash)
        configured = configuration_schema["default_model"] if configured.blank? && configuration_schema.is_a?(Hash)
        return configured if configured.present?

        preferred_chat_model
      end

      # The default CHAT model, from the synced catalog: the type's catalog
      # default when the sync returned it (exact id, else its dated variant),
      # else the lightest chat-capable model. Search, preview, embedding,
      # audio, image, moderation and completion-only ids are never candidates.
      def preferred_chat_model
        all_ids = Array(available_models).filter_map { |entry| ::Ai::ModelTiers.id_for(entry).presence }
        return nil if all_ids.empty?

        # When the filter leaves nothing (a catalog of unusual ids), the
        # lightest of ALL ids beats having no default at all.
        ids = all_ids.select { |id| ::Ai::ModelTiers.chat_capable?(id) }
        if ids.empty?
          # ...but only for a provider that claims to chat; an embedding-only
          # provider has no chat default to offer.
          return nil unless (Array(capabilities) & %w[chat text_generation]).any?

          ids = all_ids
        end

        wanted = ::Ai::ProviderCatalog.for(provider_type)&.dig(:default_chat_model)
        if wanted.present?
          preferred = ids.find { |id| id == wanted } || ids.select { |id| id.start_with?("#{wanted}-") }.min_by(&:length)
          return preferred if preferred
        end

        lightest_of(ids)
      end

      # Lightest Ai::ModelTiers tier wins; catalog position breaks a tie, so two
      # unclassifiable ids (both :standard) keep the order sync gave them.
      def lightest_catalog_model
        lightest_of(Array(available_models).filter_map { |entry| ::Ai::ModelTiers.id_for(entry).presence })
      end

      def lightest_of(ids)
        ids.each_with_index.min_by { |id, position| [ ::Ai::ModelTiers::ORDER.index(::Ai::ModelTiers.classify(id)), position ] }&.first
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
