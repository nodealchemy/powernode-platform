# frozen_string_literal: true

module Ai
  module Providers
    # Saves a provider edit and, when the edit can change what the provider
    # serves, syncs its models inline (bounded) so the operator sees the
    # outcome on save instead of waiting for the worker's sweep.
    #
    #   * an edit to a connection attribute (Ai::Provider::CONNECTION_ATTRIBUTES)
    #     syncs after the save; a failure leaves the provider as it was (an
    #     active one keeps its old models until the background retry, which
    #     disables it if it fails too: the outcome carries that warning);
    #   * an edit that turns the provider ON saves every other attribute first,
    #     then syncs and activates on a sync that returned models. A sync that
    #     deferred itself for want of a credential activates on the models the
    #     provider already has. Otherwise the other edits stay saved, the
    #     provider stays inactive and the outcome carries the sync's reason;
    #   * a type with no live sync activates on the models the operator supplied;
    #   * any other edit (name, description, priority, rate limits...) only saves.
    #
    # The model's after_commit flags a connection change for the sweep before
    # the inline sync runs; a successful inline sync clears that flag, a failed
    # or timed-out one leaves it (ModelSyncAndActivate re-flags on failure), so
    # the sweep retries only what did not sync here.
    class UpdateWithModelSync
      Outcome = Struct.new(:saved, :sync, :activation_failed, :message, :warning, :became_default, :changes,
                           keyword_init: true)

      def self.call(provider, attrs)
        new(provider, attrs).call
      end

      def initialize(provider, attrs)
        @provider = provider
        @attrs = attrs
      end

      def call
        activating = turning_on?
        @was_default = @provider.metadata&.dig("is_default") == true
        @provider.assign_attributes(activating ? @attrs.except(:is_active, "is_active") : @attrs)
        @changes = @provider.changed
        connection_changed = @changes.intersect?(::Ai::Provider::CONNECTION_ATTRIBUTES)

        return outcome(saved: false) unless @provider.save

        if activating
          activate
        elsif connection_changed && @provider.live_model_sync? && !deactivated?
          resync
        else
          outcome
        end
      end

      private

      def outcome(saved: true, **fields)
        Outcome.new(saved: saved, changes: @changes, became_default: became_default?, **fields)
      end

      def turning_on?
        raw = @attrs[:is_active].nil? ? @attrs["is_active"] : @attrs[:is_active]
        ActiveModel::Type::Boolean.new.cast(raw) == true && !@provider.is_active?
      end

      # Saved in this request with is_active going false: a deactivation never
      # syncs (the model's after_commit skips it too).
      def deactivated?
        @provider.saved_change_to_is_active? && !@provider.is_active?
      end

      def became_default?
        !@was_default && @provider.metadata&.dig("is_default") == true
      end

      def resync
        sync = run_sync(activate: false)
        warning = nil
        # The sweep's retry deactivates a provider whose sync fails again; a
        # skip (no credential) never deactivates, so it needs no warning.
        if !sync.success && !sync.skipped && @provider.is_active?
          warning = "#{@provider.name} was saved and keeps its previous models for now, but its model sync " \
                    "against #{display_url} failed: #{reason(sync)}. It will be disabled if the background retry also fails."
        end
        outcome(sync: sync, warning: warning)
      end

      def activate
        @changes |= %w[is_active]
        # A type with no live model sync activates on the models the operator
        # supplied, as before; the presence validation still guards it.
        return activate_on_current_models(nil) unless @provider.live_model_sync?

        sync = run_sync(activate: true)
        return outcome(sync: sync) if sync.success && @provider.is_active?
        # No credential to sync with: the models the provider has are as good
        # as they were; only a provider with none at all is refused.
        return activate_on_current_models(sync) if sync.skipped && @provider.supported_models.present?

        refused(sync, reason(sync))
      end

      def activate_on_current_models(sync)
        return outcome(sync: sync) if @provider.update(is_active: true)

        refused(sync, @provider.errors.full_messages.to_sentence)
      end

      def refused(sync, why)
        outcome(sync: sync, activation_failed: true, message: activation_message(why))
      end

      def run_sync(activate:)
        sync = ModelSyncAndActivate.call(@provider, activate: activate, preserve_on_failure: true, budget: true)
        @provider.reload
        @provider.clear_model_sync_pending! if sync.success
        sync
      end

      def reason(sync)
        ::Ai::ProviderManagementService.redact_sync_error(sync.error.presence || "Model sync returned no models")
      end

      # Names the provider, the URL the sync used (without its credentials)
      # and the reason, which is already redacted.
      def activation_message(why)
        why = ::Ai::ProviderManagementService.redact_sync_error(why)
        url = display_url
        where = url.present? && !why.include?(url) ? " (model sync against #{url})" : ""
        "Could not enable #{@provider.name}#{where}: #{why}. Other changes were saved; the provider stays inactive."
      end

      def display_url
        url = @provider.api_base_url.to_s.chomp("/")
        url.present? ? ::Ai::ProviderManagementService.redact_sync_error(url) : nil
      end
    end
  end
end
