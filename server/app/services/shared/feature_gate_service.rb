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

    # A feature is "core" when no loaded extension declares it as a capability.
    # Resolved through the registry so core never names a specific extension.
    # @param feature [String]
    # @return [Boolean]
    def self.core_feature?(feature)
      !Powernode::ExtensionRegistry.provides?(feature)
    end

    # Generic presence gate: is some loaded extension declaring this capability?
    #
    # Use for guarding code paths / models / associations that only exist when an
    # extension is loaded (e.g. capability_present?(:subscriptions) before touching
    # Account#subscription). Pure presence — independent of license/flag — so a loaded
    # but unlicensed extension still reports its capability as present. For a licensed,
    # account-scoped check use #available? instead.
    # @param capability [String, Symbol]
    # @return [Boolean]
    def self.capability_present?(capability)
      Powernode::ExtensionRegistry.provides?(capability)
    end

    # Check if a specific extension is loaded
    # @param slug [String]
    # @return [Boolean]
    def self.extension_loaded?(slug)
      Powernode::ExtensionRegistry.loaded?(slug)
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

    # Extensions present on disk that ship a frontend component, with their
    # enabled state. Enumerated from ExtensionPaths (NOT the loaded-engine
    # registry) so an extension's frontend availability is reported independent
    # of whether its backend engine is loaded in this process — which is what
    # the runtime frontend loader needs to decide which dedicated-module
    # bundles to fetch. Malformed manifests and extensions without a frontend
    # component are skipped.
    # @return [Array<Hash{slug:String, version:(String,nil), enabled:Boolean}>]
    def self.frontend_extensions
      Shared::ExtensionPaths.extension_dirs.filter_map do |dir|
        manifest_path = dir.join("extension.json")
        next unless manifest_path.exist?

        manifest = begin
          JSON.parse(manifest_path.read)
        rescue JSON::ParserError
          nil
        end
        next if manifest.nil?
        next unless manifest.dig("components", "frontend")

        slug = manifest["slug"].presence || dir.basename.to_s
        {
          slug: slug,
          version: manifest["version"],
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
