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

    # A feature is "core" when no loaded extension declares ownership of it.
    # Resolved through the registry so core never names a specific extension.
    # @param feature [String]
    # @return [Boolean]
    def self.core_feature?(feature)
      !Powernode::ExtensionRegistry.feature_owned?(feature)
    end

    # Check if a specific extension is loaded
    # @param slug [String]
    # @return [Boolean]
    def self.extension_loaded?(slug)
      Powernode::ExtensionRegistry.loaded?(slug)
    end

    # Check if the business engine is loaded
    # @return [Boolean]
    def self.business_loaded?
      extension_loaded?("business")
    end

    # Check if business mode is enabled via Flipper
    # Returns true if Flipper is unavailable (default enabled when loaded)
    # @return [Boolean]
    def self.business_enabled?
      return false unless business_loaded?

      flipper_enabled?(:business_mode)
    end

    # Check if a specific extension is enabled.
    #
    # An extension is considered enabled iff:
    #   1. Its manifest is present on disk (extensions/<slug>/extension.json)
    #   2. It is NOT marked disabled in config/extensions_state.json (load-time gate)
    #   3. Its Flipper flag (<slug>_mode) is enabled (runtime gate)
    #
    # The first two conditions can be evaluated even when the engine is not
    # loaded into the current process, which lets the admin UI display the
    # correct state for an extension that was disabled at boot.
    #
    # @param slug [String]
    # @return [Boolean]
    def self.extension_enabled?(slug)
      return false unless extension_manifest_present?(slug)
      return false if Shared::ExtensionStateStore.disabled?(slug)

      flipper_enabled?(:"#{slug.tr('-', '_')}_mode")
    end

    # Check if an extension's manifest exists on disk. This is process-independent
    # and survives engine unload — used by the admin UI to enumerate toggleable
    # extensions even when their engines are not currently loaded.
    # @param slug [String]
    # @return [Boolean]
    def self.extension_manifest_present?(slug)
      Shared::ExtensionPaths.manifest_present?(slug)
    end

    # Check if running in core (self-hosted) mode
    # @return [Boolean]
    def self.core_mode?
      Powernode::ExtensionRegistry.slugs.empty?
    end

    # Check if billing features are available
    # @return [Boolean]
    def self.billing_enabled?
      business_enabled?
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

    # Toggle an extension's "<slug>_mode" Flipper flag (generic).
    # @param slug [String]
    # @param enabled [Boolean]
    # @return [Boolean] new enabled state
    def self.set_extension_enabled!(slug, enabled)
      return false unless extension_loaded?(slug)
      return false unless defined?(Flipper)

      flag = :"#{slug.tr('-', '_')}_mode"
      enabled ? Flipper.enable(flag) : Flipper.disable(flag)
      extension_enabled?(slug)
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
