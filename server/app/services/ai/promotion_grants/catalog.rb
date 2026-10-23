# frozen_string_literal: true

module Ai
  module PromotionGrants
    # What core asks the extension that owns a grantable verb (core purity:
    # core never names the verb's permission or its subjects). The extension
    # registers a provider under PROVIDER_KEY (Powernode::ExtensionRegistry)
    # answering, for a category Ai::PromotionGrants::Grantable admits:
    #
    #   required_permission(category)              -> String | nil
    #     the permission the gated verb itself requires. A granter must hold it.
    #   subjects(account:, action_category:)       -> [{ id:, name: }]
    #     what a grant may name in module_ids (the form's multi-select).
    #   unknown_subject_ids(account:, action_category:, ids:) -> [String]
    #     the ids that name nothing of this account's.
    #
    # No provider (core mode) answers nil / [], and a nil permission refuses
    # issue: a grant for a verb nobody declared can never be honoured anyway.
    module Catalog
      PROVIDER_KEY = :promotion_grant_catalog

      module_function

      def provider
        ::Powernode::ExtensionRegistry.provider(PROVIDER_KEY)
      end

      def required_permission(category)
        return nil unless ::Ai::PromotionGrants::Grantable.grantable?(category)

        provider&.required_permission(category.to_s).presence
      end

      def subjects(account:, action_category:)
        return [] unless ::Ai::PromotionGrants::Grantable.grantable?(action_category)

        Array(provider&.subjects(account: account, action_category: action_category.to_s))
      end

      # With no provider every id is unknown: nothing can vouch for it.
      def unknown_subject_ids(account:, action_category:, ids:)
        ids = Array(ids).map(&:to_s)
        return ids if ids.empty? || provider.nil?

        Array(provider.unknown_subject_ids(account: account, action_category: action_category.to_s, ids: ids))
      end
    end
  end
end
