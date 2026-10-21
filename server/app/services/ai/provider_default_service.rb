# frozen_string_literal: true

module Ai
  # The account's default AI provider, on the EXISTING default mechanism:
  # priority_order 1 (Provider.default, #is_default?) plus the metadata
  # is_default flag Provider.default_for_account reads. No parallel flag.
  #
  # Only a provider that can actually serve a call may be chosen: active,
  # routable (never the Claude Code local-sessions scope), holding synced
  # models and an active credential. A provider whose model sync failed is
  # deactivated with its models cleared, so it fails this test by construction.
  class ProviderDefaultService
    class NotEligible < StandardError; end

    class << self
      def eligible?(provider)
        provider.is_active? &&
          provider.platform_routable? &&
          provider.supported_models.present? &&
          provider.provider_credentials.any?(&:is_active)
      end

      # Makes `provider` the account default: first in priority order and the
      # only provider flagged is_default. Everything else keeps its relative
      # order behind it.
      def set_default!(provider, skip_eligibility: false)
        raise NotEligible, ineligible_reason(provider) unless skip_eligibility || eligible?(provider)

        ::Ai::Provider.transaction do
          siblings = ::Ai::Provider.where(account_id: provider.account_id).where.not(id: provider.id)
                                   .order(:priority_order, :name).lock.to_a
          ([ provider ] + siblings).each_with_index do |record, index|
            flagged = record.id == provider.id
            record.update_columns(
              priority_order: index + 1,
              metadata: (record.metadata || {}).merge("is_default" => flagged),
              updated_at: Time.current
            )
          end
        end
        provider.reload
      end

      # The first working provider becomes the default on its own; a later
      # one does not displace an operator's working choice.
      def ensure_default!(provider)
        return false unless eligible?(provider)

        current = ::Ai::Provider.default_for_account(provider.account)
        return false if current && current.id != provider.id && eligible?(current)

        set_default!(provider)
        true
      end

      private

      def ineligible_reason(provider)
        return "Provider is inactive" unless provider.is_active?
        return "Provider cannot serve platform requests" unless provider.platform_routable?
        return "Provider has no synced models" if provider.supported_models.blank?

        "Provider has no active credential"
      end
    end
  end
end
