# frozen_string_literal: true

module Shared
  # Per-category provider-credential presence for an account (ai / cloud / git).
  #
  # Single source of truth shared by the onboarding status endpoint and
  # Setup::StepRegistry (which resolves the provider steps' completion from
  # credential presence). Each category is guarded by `respond_to?` so it stays
  # usable in core mode (System/Git extensions disabled) and on installs that
  # haven't pulled all extensions — an absent association reports has_credentials:false.
  module ProviderCredentialState
    CATEGORY_ASSOCIATIONS = {
      ai: :ai_provider_credentials,
      cloud: :system_provider_credentials,
      git: :git_provider_credentials
    }.freeze

    module_function

    # @return [Hash{Symbol=>Hash}] { ai: {has_credentials:,count:,available:}, cloud: {...}, git: {...} }
    def category_states(account)
      CATEGORY_ASSOCIATIONS.transform_values { |assoc| credential_state(account, assoc) }
    end

    # @param category [Symbol, String] :ai | :cloud | :git
    def has_credentials?(account, category)
      assoc = CATEGORY_ASSOCIATIONS[category.to_sym]
      return false unless assoc

      credential_state(account, assoc)[:has_credentials]
    end

    def credential_state(account, association_name)
      return { has_credentials: false, count: 0, available: false } unless account.respond_to?(association_name)

      scope = account.public_send(association_name)
      scope = scope.where(is_active: true) if scope.model.column_names.include?("is_active")
      count = scope.count

      { has_credentials: count.positive?, count: count, available: true }
    end
  end
end
