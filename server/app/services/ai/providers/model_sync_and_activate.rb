# frozen_string_literal: true

module Ai
  module Providers
    # Syncs a provider's models server-side and reports the outcome, so the
    # setup wizard and the providers page show a count or the error instead of
    # a provider that silently has no models.
    #
    #   * on a successful sync (and `activate: true`) the provider is activated;
    #   * a failure is reported in the result, never swallowed or raised;
    #   * the first working provider becomes the account default.
    #
    # Nothing here reads or returns credential material.
    class ModelSyncAndActivate
      Result = Struct.new(:success, :deferred, :model_count, :error, :activated, :default, keyword_init: true) do
        def to_h
          { success: success, deferred: deferred, model_count: model_count, error: error,
            activated: activated, default: default }
        end
      end

      # Types with a live model-list sync. Any other type falls to the generic
      # placeholder sync, which would overwrite the models the operator
      # supplied, so it is left alone.
      SYNCABLE_TYPES = %w[ollama openai anthropic google azure azure_openai groq grok xai mistral cohere].freeze

      def self.call(provider, activate: true)
        new(provider, activate: activate).call
      end

      def initialize(provider, activate:)
        @provider = provider
        @activate = activate
      end

      def call
        return unsupported unless SYNCABLE_TYPES.include?(@provider.provider_type.to_s.downcase)

        ok = ::Ai::ProviderManagementService.sync_provider_models(@provider, force_refresh: true)
        @provider.reload
        return failure(ok) unless ok && @provider.supported_models.present?

        activated = activate!
        made_default = @activate && ::Ai::ProviderDefaultService.ensure_default!(@provider.reload)
        Result.new(success: true, deferred: false, model_count: @provider.supported_models.size,
                   error: nil, activated: activated, default: made_default || default_now?)
      rescue StandardError => e
        Rails.logger.error("[Ai::Providers::ModelSyncAndActivate] #{e.class} for provider #{@provider.id}")
        Result.new(success: false, deferred: false, model_count: 0, error: e.message.to_s.truncate(300),
                   activated: false, default: false)
      end

      private

      def activate!
        return false unless @activate
        return false if @provider.is_active?

        @provider.update!(is_active: true)
        true
      end

      def default_now?
        @provider.metadata&.dig("is_default") == true
      end

      def unsupported
        Result.new(success: false, deferred: true, model_count: @provider.supported_models&.size.to_i,
                   error: "No live model sync for this provider type", activated: false, default: false)
      end

      def failure(_ok)
        metadata = @provider.metadata || {}
        skipped = metadata["last_sync_skipped_reason"].present? && metadata["last_sync_error"].blank?
        error = metadata["last_sync_error"].presence || metadata["last_sync_skipped_reason"].presence ||
                "Model sync returned no models"
        Result.new(success: false, deferred: skipped, model_count: @provider.supported_models&.size.to_i,
                   error: error, activated: false, default: false)
      end
    end
  end
end
