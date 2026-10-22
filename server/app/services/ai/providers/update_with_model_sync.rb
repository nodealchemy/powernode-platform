# frozen_string_literal: true

module Ai
  module Providers
    # Saves a provider edit and, when the edit can change what the provider
    # serves, syncs its models inline (bounded) so the operator sees the
    # outcome on save instead of waiting for the worker's sweep.
    #
    #   * an edit to a connection attribute (Ai::Provider::CONNECTION_ATTRIBUTES)
    #     syncs after the save; a failure leaves the provider as it was
    #     (an active one keeps its old models) and reports the failure;
    #   * an edit that turns the provider ON saves every other attribute first,
    #     then syncs and activates only on a sync that returned models; on a
    #     failure the other edits stay saved, the provider stays inactive and
    #     the outcome carries the sync's reason;
    #   * any other edit (name, description, priority, rate limits...) only saves.
    #
    # The model's after_commit flags a connection change for the sweep before
    # the inline sync runs; a successful inline sync clears that flag, a failed
    # or timed-out one leaves it (ModelSyncAndActivate re-flags on failure), so
    # the sweep retries only what did not sync here.
    class UpdateWithModelSync
      Outcome = Struct.new(:saved, :sync, :activation_failed, :message, :changes, keyword_init: true)

      def self.call(provider, attrs)
        new(provider, attrs).call
      end

      def initialize(provider, attrs)
        @provider = provider
        @attrs = attrs
      end

      def call
        activating = turning_on?
        @provider.assign_attributes(activating ? @attrs.except(:is_active, "is_active") : @attrs)
        changes = @provider.changed
        connection_changed = changes.intersect?(::Ai::Provider::CONNECTION_ATTRIBUTES)

        return Outcome.new(saved: false, changes: changes) unless @provider.save

        if activating
          activate(changes)
        elsif connection_changed && syncable? && !deactivated?
          sync = run_sync(activate: false)
          Outcome.new(saved: true, sync: sync, changes: changes)
        else
          Outcome.new(saved: true, changes: changes)
        end
      end

      private

      def turning_on?
        raw = @attrs[:is_active].nil? ? @attrs["is_active"] : @attrs[:is_active]
        ActiveModel::Type::Boolean.new.cast(raw) == true && !@provider.is_active?
      end

      # Saved in this request with is_active going false: a deactivation never
      # syncs (the model's after_commit skips it too).
      def deactivated?
        @provider.saved_change_to_is_active? && !@provider.is_active?
      end

      def syncable?
        ModelSyncAndActivate::SYNCABLE_TYPES.include?(@provider.provider_type.to_s.downcase)
      end

      def activate(changes)
        changes |= %w[is_active]
        # A type with no live model sync activates on the models the operator
        # supplied, as before; the presence validation still guards it.
        unless syncable?
          return Outcome.new(saved: true, changes: changes) if @provider.update(is_active: true)

          return Outcome.new(saved: true, activation_failed: true, changes: changes,
                             message: activation_message(@provider.errors.full_messages.to_sentence))
        end

        sync = run_sync(activate: true)
        return Outcome.new(saved: true, sync: sync, changes: changes) if sync.success && @provider.is_active?

        Outcome.new(saved: true, sync: sync, activation_failed: true, changes: changes,
                    message: activation_message(sync.error.presence || "Model sync returned no models"))
      end

      def run_sync(activate:)
        sync = ModelSyncAndActivate.call(@provider, activate: activate, preserve_on_failure: true, budget: true)
        @provider.reload
        @provider.clear_model_sync_pending! if sync.success
        sync
      end

      # Names the provider, the URL the sync used (without its credentials)
      # and the sync's own reason. The reason is the sync's error text, which
      # is already redacted (ProviderManagementService.redact_sync_error).
      def activation_message(reason)
        reason = ::Ai::ProviderManagementService.redact_sync_error(reason)
        url = display_url
        where = url.present? && !reason.include?(url) ? " (model sync against #{url})" : ""
        "Could not enable #{@provider.name}#{where}: #{reason}. Other changes were saved; the provider stays inactive."
      end

      def display_url
        url = @provider.api_base_url.to_s.chomp("/")
        url.present? ? ::Ai::ProviderManagementService.redact_sync_error(url) : nil
      end
    end
  end
end
