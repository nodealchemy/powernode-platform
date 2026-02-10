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

      # Check master enterprise_mode toggle
      return false unless enterprise_enabled?

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

    # Check if enterprise mode is enabled via Flipper
    # Returns true if Flipper is unavailable (default enabled when loaded)
    # @return [Boolean]
    def self.enterprise_enabled?
      return false unless enterprise_loaded?
      return true unless defined?(Flipper)

      Flipper.enabled?(:enterprise_mode)
    rescue StandardError
      true
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
      info = {
        enterprise_installed: enterprise_loaded?,
        enterprise_enabled: enterprise_enabled?
      }

      if enterprise_loaded?
        info[:engine_version] = PowernodeEnterprise::VERSION if defined?(PowernodeEnterprise::VERSION)
        info[:license_valid] = PowernodeEnterprise::License.valid? if defined?(PowernodeEnterprise::License)
        info[:license_edition] = PowernodeEnterprise::License.edition if defined?(PowernodeEnterprise::License)

        if defined?(PowernodeEnterprise::Features::ENTERPRISE_FLAGS)
          info[:feature_flags] = PowernodeEnterprise::Features::ENTERPRISE_FLAGS.map do |flag|
            {
              name: flag.to_s,
              enabled: defined?(Flipper) ? Flipper.enabled?(flag) : false
            }
          rescue StandardError
            { name: flag.to_s, enabled: false }
          end
        end
      end

      info
    end
  end
end
