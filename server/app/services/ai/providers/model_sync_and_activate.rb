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
      Result = Struct.new(:success, :deferred, :model_count, :error, :activated, :default, :remaining_seconds, keyword_init: true) do
        def to_h
          { success: success, deferred: deferred, model_count: model_count, error: error,
            activated: activated, default: default }
        end
      end

      # Types with a live model-list sync. Any other type falls to the generic
      # placeholder sync, which would overwrite the models the operator
      # supplied, so it is left alone.
      SYNCABLE_TYPES = %w[ollama openai anthropic google azure azure_openai groq grok xai mistral cohere].freeze

      # One total time budget for a create-time sync, however many requests
      # (and fallbacks) the type's sync makes.
      CREATE_BUDGET_SECONDS = 10

      # activate:             activate the provider on success
      # credential:           sync with THIS credential (the one just saved), not
      #                       whichever active credential happens to come first
      # preserve_on_failure:  a failure leaves the provider exactly as it was and
      #                       flags it for the worker's retry (create time)
      # budget:               bound the whole sync by a CREATE_BUDGET_SECONDS
      #                       deadline the HTTP calls honour (no thread interrupt)
      def self.call(provider, activate: true, credential: nil, preserve_on_failure: false, budget: false)
        new(provider, activate: activate, credential: credential,
                      preserve_on_failure: preserve_on_failure, budget: budget).call
      end

      def initialize(provider, activate:, credential:, preserve_on_failure:, budget:)
        @provider = provider
        @activate = activate
        @credential = credential
        @preserve = preserve_on_failure
        @budget = budget
      end

      def call
        return unsupported unless SYNCABLE_TYPES.include?(@provider.provider_type.to_s.downcase)

        snapshot = @snapshot = take_snapshot
        # A provider that already works and has another active credential must
        # survive a bad new key: the failure is recorded on the credential.
        protect = @preserve || already_working_elsewhere?(snapshot)

        ok = run_sync
        @provider.reload
        unless ok && @provider.supported_models.present?
          return protect ? restore_after_failure(snapshot) : failure(ok)
        end

        activated = activate!
        made_default = @activate && ::Ai::ProviderDefaultService.ensure_default!(@provider.reload)
        Result.new(success: true, deferred: false, model_count: @provider.supported_models.size,
                   error: nil, activated: activated, default: made_default || default_now?,
                   remaining_seconds: remaining)
      rescue StandardError => e
        Rails.logger.error("[Ai::Providers::ModelSyncAndActivate] #{e.class} for provider #{@provider.id}")
        Result.new(success: false, deferred: false, model_count: 0, error: e.message.to_s.truncate(300),
                   activated: false, default: false)
      end

      private

      def run_sync
        @deadline = @budget ? now + CREATE_BUDGET_SECONDS : nil
        @provider.with_sync_options(credential: @credential, deadline: @deadline) do
          ::Ai::ProviderManagementService.sync_provider_models(@provider, force_refresh: true)
        end
      end

      # Seconds left of the budget, for the caller's next step (the credential's
      # connection test). nil when the sync was not budgeted.
      def remaining
        @deadline && [ @deadline - now, 0 ].max
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def take_snapshot
        @provider.reload
        { is_active: @provider.is_active, supported_models: @provider.supported_models, metadata: @provider.metadata }
      end

      def already_working_elsewhere?(snapshot)
        @credential && snapshot[:supported_models].present? &&
          @provider.provider_credentials.active.where.not(id: @credential.id).exists?
      end

      # Put the provider back as it was; the failure is the credential's (when
      # one was being added) or a deferred retry (create time).
      def restore_after_failure(snapshot, reason: nil, force_deferred: false)
        @provider.reload
        error = reason || @provider.metadata&.dig("last_sync_error").presence || "Model sync failed"
        @provider.update_columns(is_active: snapshot[:is_active], supported_models: snapshot[:supported_models],
                                 metadata: snapshot[:metadata])
        @provider.reload
        if @credential
          @credential.record_failure!(error.to_s.truncate(300))
        else
          @provider.mark_model_sync_pending!
        end
        spent = @deadline.present? && remaining.zero?
        Result.new(success: false, deferred: force_deferred || @credential.nil? || spent,
                   model_count: @provider.supported_models&.size.to_i,
                   error: error.to_s.truncate(300), activated: false, default: false, remaining_seconds: remaining)
      end

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
