# frozen_string_literal: true

module Shared
  class FeatureGateService
    # Check if a feature is available for the given context
    #
    # Core features always return true.
    # Enterprise features require the engine present + valid license + plan check + feature flag.
    #
    # @param feature [String] Feature name (e.g., "baas", "credits", "governance")
    # @param account [Account, nil] Account to check against
    # @param user [User, nil] User to check permissions for
    # @return [Boolean]
    def self.available?(feature, account: nil, user: nil)
      # Core features are always available
      return true if core_feature?(feature)

      # Enterprise features require the engine
      return false unless defined?(PowernodeEnterprise::Engine)

      # Delegate to enterprise features module
      PowernodeEnterprise::Features.available?(feature, account: account)
    end

    # @param feature [String]
    # @return [Boolean]
    def self.core_feature?(feature)
      !enterprise_feature?(feature)
    end

    # @param feature [String]
    # @return [Boolean]
    def self.enterprise_feature?(feature)
      return false unless defined?(PowernodeEnterprise::Features)

      PowernodeEnterprise::Features::FEATURE_TIERS.key?(feature.to_s)
    end

    # Check if the enterprise engine is loaded
    # @return [Boolean]
    def self.enterprise_loaded?
      defined?(PowernodeEnterprise::Engine).present?
    end
  end
end
