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
      # skipped: the sync deferred itself because no credential could make the
      # call (handle_sync_skipped); nothing was fetched and nothing changed.
      Result = Struct.new(:success, :deferred, :skipped, :model_count, :error, :activated, :default, :remaining_seconds,
                          keyword_init: true) do
        def to_h
          { success: success, deferred: deferred, skipped: skipped || false, model_count: model_count, error: error,
            activated: activated, default: default }
        end
      end

      # What a sync writes to metadata. A failed sync puts back exactly these,
      # leaving every other key as the row holds it now.
      SYNC_METADATA_KEYS = %w[last_sync_error last_sync_failed_at last_sync_skipped_at last_sync_skipped_reason].freeze

      # Types with a live model-list sync. Any other type falls to the generic
      # placeholder sync, which would overwrite the models the operator
      # supplied, so it is left alone.
      SYNCABLE_TYPES = %w[ollama openai anthropic google azure azure_openai groq grok xai mistral cohere].freeze

      # One total time budget for a create-time sync, however many requests
      # (and fallbacks) the type's sync makes. Each request's http.rb global
      # timeout is cut to what is left of it, and that timeout wraps socket open
      # (DNS included) as well as the read. Name resolution is a blocking
      # getaddrinfo call, which Ruby's Timeout may not be able to interrupt on
      # this Ruby (3.2): a stalled resolver can overrun the budget by up to its
      # own timeout (resolv.conf `timeout` x `attempts`, per nameserver).
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
          return protect ? restore_after_failure(snapshot, ok: ok) : failure(ok)
        end

        activated = activate!
        made_default = @activate && ::Ai::ProviderDefaultService.ensure_default!(@provider.reload)
        Result.new(success: true, deferred: false, model_count: @provider.supported_models.size,
                   error: nil, activated: activated, default: made_default || default_now?,
                   remaining_seconds: remaining)
      rescue StandardError => e
        Rails.logger.error("[Ai::Providers::ModelSyncAndActivate] #{e.class} for provider #{@provider.id}")
        Result.new(success: false, deferred: false, model_count: 0,
                   error: ::Ai::ProviderManagementService.redact_sync_error(e.message).truncate(300),
                   activated: false, default: false)
      end

      private

      def run_sync
        @deadline = @budget ? now + CREATE_BUDGET_SECONDS : nil
        @provider.with_sync_options(credential: @credential, deadline: @deadline) do
          ok = ::Ai::ProviderManagementService.sync_provider_models(@provider, force_refresh: true)
          @skipped_reason = @provider.sync_skipped_reason
          ok
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
      def restore_after_failure(snapshot, ok: false, reason: nil, force_deferred: false)
        @provider.reload
        error = reason || failure_reason(ok)
        restore_sync_state(snapshot)
        @provider.reload
        if @credential
          @credential.record_failure!(error.to_s.truncate(300))
        else
          @provider.mark_model_sync_pending!
        end
        spent = @deadline.present? && remaining.zero?
        Result.new(success: false, deferred: force_deferred || @credential.nil? || spent, skipped: skipped?,
                   model_count: @provider.supported_models&.size.to_i,
                   error: error.to_s.truncate(300), activated: false, default: false, remaining_seconds: remaining)
      end

      # Undo what the failed sync wrote, and only that, compare-and-set against
      # the stored row, so a write that landed while the HTTP calls were in
      # flight (make_default, an operator edit, the pending flag) survives:
      #   * is_active / supported_models go back only while the row still holds
      #     what a failed sync leaves (inactive, no models);
      #   * metadata gets back its snapshot values for SYNC_METADATA_KEYS only.
      def restore_sync_state(snapshot)
        before = (snapshot[:metadata] || {}).slice(*SYNC_METADATA_KEYS)
        ::Ai::Provider.transaction do
          ::Ai::Provider.where(id: @provider.id, is_active: false).where("supported_models = '[]'::jsonb")
                        .update_all(is_active: snapshot[:is_active], supported_models: snapshot[:supported_models] || [])
          @provider.merge_metadata!(set: before, remove: SYNC_METADATA_KEYS - before.keys)
        end
      end

      def skipped?
        @skipped_reason.present?
      end

      # This run's reason, never a stale one: a skip names its own reason; a
      # sync that answered with nothing says so; a failed one recorded its
      # error just now (record_sync_failure).
      def failure_reason(ok)
        return @skipped_reason if skipped?
        return "Model sync returned no models" if ok

        @provider.metadata&.dig("last_sync_error").presence || "Model sync failed"
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

      def failure(ok)
        Result.new(success: false, deferred: skipped?, skipped: skipped?, model_count: @provider.supported_models&.size.to_i,
                   error: failure_reason(ok), activated: false, default: false)
      end
    end
  end
end
