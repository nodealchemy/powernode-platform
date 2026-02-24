# frozen_string_literal: true

module Shared
  class FeatureGateService
    # Check if a feature is available for the given context
    #
    # Core features always return true.
    # Extension features are delegated to the extension registry.
    #
    # @param feature [String] Feature name (e.g., "baas", "credits", "governance")
    # @param account [Account, nil] Account to check against
    # @param user [User, nil] User to check permissions for
    # @return [Boolean]
    def self.available?(feature, account: nil, user: nil)
      return true if core_feature?(feature)

      Powernode::ExtensionRegistry.feature_available?(feature, account: account)
    end

    # @param feature [String]
    # @return [Boolean]
    def self.core_feature?(feature)
      !enterprise_feature?(feature)
    end

    # @param feature [String]
    # @return [Boolean]
    def self.enterprise_feature?(feature)
      return false unless extension_loaded?("enterprise")

      engine = Powernode::ExtensionRegistry.engine_for("enterprise")
      features_mod = "PowernodeEnterprise::Features".safe_constantize
      return false unless features_mod&.const_defined?(:FEATURE_TIERS)

      features_mod::FEATURE_TIERS.key?(feature.to_s)
    end

    # Check if a specific extension is loaded
    # @param slug [String]
    # @return [Boolean]
    def self.extension_loaded?(slug)
      Powernode::ExtensionRegistry.loaded?(slug)
    end

    # Check if the enterprise engine is loaded
    # @return [Boolean]
    def self.enterprise_loaded?
      extension_loaded?("enterprise")
    end

    # Check if enterprise mode is enabled via Flipper
    # Returns true if Flipper is unavailable (default enabled when loaded)
    # @return [Boolean]
    def self.enterprise_enabled?
      return false unless enterprise_loaded?

      flipper_enabled?(:enterprise_mode)
    end

    # Check if a specific extension is enabled
    # @param slug [String]
    # @return [Boolean]
    def self.extension_enabled?(slug)
      return false unless extension_loaded?(slug)

      flipper_enabled?(:"#{slug.tr('-', '_')}_mode")
    end

    # Check if running in core (self-hosted) mode
    # @return [Boolean]
    def self.core_mode?
      Powernode::ExtensionRegistry.slugs.empty?
    end

    # Check if billing features are available
    # @return [Boolean]
    def self.billing_enabled?
      enterprise_enabled?
    end

    # Get list of loaded extensions with their status
    # @return [Array<Hash>]
    def self.loaded_extensions
      Powernode::ExtensionRegistry.all.map do |slug, ext|
        {
          slug: slug,
          version: ext[:version],
          enabled: extension_enabled?(slug)
        }
      end
    end

    # Toggle the enterprise_mode Flipper flag
    # @param enabled [Boolean]
    # @return [Boolean] new state
    def self.set_enterprise_enabled!(enabled)
      return false unless enterprise_loaded?
      return false unless defined?(Flipper)

      if enabled
        Flipper.enable(:enterprise_mode)
      else
        Flipper.disable(:enterprise_mode)
      end

      enterprise_enabled?
    end

    # Development info payload for admin UI
    # @return [Hash]
    def self.development_info
      {
        extensions: loaded_extensions
      }
    end

    private_class_method def self.flipper_enabled?(flag)
      return true unless defined?(Flipper)

      Flipper.enabled?(flag)
    rescue StandardError
      true
    end
  end
end
