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
      # order behind it. Unpinned, resolver-minted agent clones follow the new
      # default; pinned ones stay where they are.
      def set_default!(provider, skip_eligibility: false)
        raise NotEligible, ineligible_reason(provider) unless skip_eligibility || eligible?(provider)

        ::Ai::Provider.transaction do
          rank!(lock_account_providers(provider.account_id), first: provider)
          repoint_unpinned_clones!(provider.account_id, to: provider)
        end
        provider.reload
      end

      # The first working provider becomes the default on its own; a later
      # one does not displace an operator's working choice.
      def ensure_default!(provider)
        return false unless eligible?(provider)

        current = ::Ai::Provider.default_for_account(provider.account)
        return false if current && current.id != provider.id

        set_default!(provider)
        true
      end

      # Called after something that may have taken the default's ability to
      # serve away (a provider or credential removed). Keeps a working default
      # if there is one; else promotes the best working provider; else clears
      # the stale flag so nothing claims to be the default.
      def heal!(account)
        return false unless account

        providers = ::Ai::Provider.where(account_id: account.id).includes(:provider_credentials).order(:priority_order, :name).to_a
        return false if providers.any? { |p| flagged?(p) && eligible?(p) }

        replacement = providers.find { |p| eligible?(p) }
        if replacement
          set_default!(replacement)
        else
          providers.select { |p| flagged?(p) }.each do |stale|
            stale.update_columns(metadata: (stale.metadata || {}).merge("is_default" => false))
          end
        end
        true
      end

      # Before a provider is destroyed: unpinned resolver-minted clones on it
      # move to the account's next working provider, so the delete is not
      # refused (agents restrict it) and the clones keep running.
      def release_clones!(provider)
        target = ::Ai::Provider.where(account_id: provider.account_id).where.not(id: provider.id)
                               .includes(:provider_credentials).order(:priority_order, :name).to_a
                               .find { |p| eligible?(p) }
        return 0 unless target

        unpinned_clones(provider.account_id).where(ai_provider_id: provider.id).update_all(ai_provider_id: target.id)
      end

      private

      def flagged?(provider)
        provider.metadata&.dig("is_default") == true
      end

      # One statement, id order, target included: two concurrent changes
      # always take the row locks in the same order, so they cannot deadlock.
      def lock_account_providers(account_id)
        ::Ai::Provider.where(account_id: account_id).order(:id).lock.to_a
      end

      def rank!(locked, first:)
        siblings = locked.reject { |p| p.id == first.id }.sort_by { |p| [ p.priority_order, p.name.to_s ] }
        ([ first ] + siblings).each_with_index do |record, index|
          record.update_columns(
            priority_order: index + 1,
            metadata: (record.metadata || {}).merge("is_default" => record.id == first.id),
            updated_at: Time.current
          )
        end
      end

      # Agents the account's principal resolver minted from a global canonical
      # and that pin no model: they have no reason to stay on an old provider.
      def unpinned_clones(account_id)
        ::Ai::Agent.where(account_id: account_id).where.not(cloned_from_id: nil)
                   .where("COALESCE(mcp_metadata -> 'model_config' ->> 'model', '') = ''")
      end

      def repoint_unpinned_clones!(account_id, to:)
        unpinned_clones(account_id).where.not(ai_provider_id: to.id).update_all(ai_provider_id: to.id)
      end

      def ineligible_reason(provider)
        return "Provider is inactive" unless provider.is_active?
        return "Provider cannot serve platform requests" unless provider.platform_routable?
        return "Provider has no synced models" if provider.supported_models.blank?

        "Provider has no active credential"
      end
    end
  end
end
