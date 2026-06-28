# frozen_string_literal: true

module Ai
  module Deploy
    # Resolves a deploy Method for a Target. Core methods register here at boot
    # (config/initializers/ai_deploy_methods.rb). Extensions contribute additional
    # methods WITHOUT core naming them: an extension registers a provider under
    # Powernode::ExtensionRegistry providers key :deploy_method_providers — a class
    # responding to #deploy_methods => { key(Symbol) => Ai::Deploy::Method subclass }.
    # In core mode the provider is absent and only core methods are available.
    #
    # Selection for a target: an explicit target.config["method"] override wins; else the
    # first available method in the per-kind default order.
    module MethodRegistry
      CORE_METHODS = {} # rubocop:disable Style/MutableConstant -- registry mutated at boot

      # Preference order per target kind. The first AVAILABLE method wins (so a prod
      # install with k8s uses kubernetes; a dev box with only the sudo bridge falls
      # through to it). Explicit config["method"] always overrides this.
      DEFAULT_ORDER = {
        Target::PLATFORM_SELF => %i[kubernetes docker sudo_bridge],
        Target::PROJECT => %i[workload kubernetes docker]
      }.freeze

      module_function

      def register(method_class)
        CORE_METHODS[method_class.key.to_sym] = method_class
        method_class
      end

      def reset_core!
        CORE_METHODS.clear
      end

      # All known methods (core + extension-provided), keyed by Symbol.
      def all
        CORE_METHODS.merge(extension_methods)
      end

      def available
        all.select { |_key, klass| safe_available?(klass) }
      end

      def fetch(key)
        all[key.to_sym]
      end

      # The Method class for a target, or nil if none is available.
      def resolve(target)
        if (explicit = target.method_key)
          klass = fetch(explicit)
          return safe_available?(klass) ? klass : nil
        end
        default_for(target)
      end

      def default_for(target)
        DEFAULT_ORDER.fetch(target.kind, [])
                     .filter_map { |k| fetch(k) }
                     .find { |klass| safe_available?(klass) }
      end

      def extension_methods
        provider = extension_provider
        return {} unless provider.respond_to?(:deploy_methods)

        provider.deploy_methods.transform_keys(&:to_sym)
      rescue StandardError => e
        Rails.logger.warn("[Deploy::MethodRegistry] extension method load failed: #{e.message}")
        {}
      end

      def extension_provider
        return nil unless defined?(::Powernode::ExtensionRegistry)

        ::Powernode::ExtensionRegistry.provider(:deploy_method_providers)
      rescue StandardError
        nil
      end

      def safe_available?(klass)
        klass.respond_to?(:available?) && klass.available?
      rescue StandardError
        false
      end
    end
  end
end
