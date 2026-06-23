# frozen_string_literal: true

module Powernode
  # Central, slug-agnostic registry of loaded extensions.
  #
  # Core integrates with extensions ONLY through the generic seams here — it never
  # names a specific extension slug. There are two distinct seams:
  #
  #   * Capabilities (presence)  — declarative symbols an extension `register`s. Core asks
  #     `provides?(:cap)` / `FeatureGateService.capability_present?(:cap)` to decide whether
  #     a code path / model / association exists in-process. Pure presence; never consults
  #     `features_module`, so a single non-compliant extension cannot poison resolution.
  #   * Providers (behavior)     — named implementations an extension `register`s. Core calls
  #     `provider(:key)` and falls back to a permissive/absent default when it returns nil
  #     (that nil-default IS core mode). This is the inversion-of-control seam: extensions
  #     inject behavior, core holds none of the extension-specific logic.
  #
  # Licensed feature availability (account-scoped) is resolved by `feature_available?`, which
  # only consults the `features_module` of an extension that DECLARES the feature as a
  # capability — so a blanket-`true` features_module in some other extension is irrelevant.
  #
  # A brand-new extension plugs in by calling `register(...)` with its capabilities/providers;
  # no edit to core is required.
  module ExtensionRegistry
    class << self
      # Register an extension at boot (engine initializer / config.after_initialize).
      #
      # @param slug [String, Symbol] extension slug (e.g. "business")
      # @param engine [Class] the Rails::Engine subclass
      # @param version [String, nil]
      # @param features_module [Module, nil] responds to `available?(feature, account:)`,
      #   returning nil for features it does not own (license/tier/flag decision otherwise)
      # @param capabilities [Array<Symbol,String>] declarative capability slugs this extension
      #   provides (presence). Stored symbolized and frozen.
      # @param providers [Hash{Symbol,String=>Object,String,#call}] named behavior providers.
      #   Values may be an object/class, a callable, or a String to constantize lazily.
      def register(slug:, engine:, version: nil, features_module: nil, capabilities: [], providers: {}, owned_prefixes: [])
        root = engine.respond_to?(:root) ? engine.root.to_s : ""
        extensions[slug.to_s] = {
          engine: engine,
          version: version,
          features_module: features_module,
          capabilities: Array(capabilities).map(&:to_sym).freeze,
          providers: providers.to_h.transform_keys(&:to_sym).freeze,
          # Table-name prefixes this extension owns (e.g. %w[business]). Drives the
          # public-schema dump exclusion for PRIVATE extensions (schema isolation).
          owned_prefixes: Array(owned_prefixes).map(&:to_s).freeze,
          # Private-by-location: extensions/private/* are remote-only (absent from
          # public clones). Derived, never hardcoded — mirrors the Gemfile split.
          private: root.include?("/extensions/private/")
        }
      end

      def loaded?(slug)
        extensions.key?(slug.to_s)
      end

      def engine_for(slug)
        extensions.dig(slug.to_s, :engine)
      end

      def slugs
        extensions.keys
      end

      def all
        extensions.dup
      end

      def each(&block)
        extensions.each(&block)
      end

      # Declarative capabilities of a single loaded extension (symbols), or [] if absent.
      def capabilities_for(slug)
        extensions.dig(slug.to_s, :capabilities) || []
      end

      # True iff ANY loaded extension declares `capability`. Pure presence: independent of
      # features_module, license, and Flipper. This is the robust seam core gates use to
      # detect that an extension's code/models are present in-process.
      def provides?(capability)
        cap = capability.to_sym
        extensions.each_value.any? { |ext| ext[:capabilities].include?(cap) }
      end

      # The first registered behavior provider for `key`, or nil when no loaded extension
      # registers one (nil ⇒ core-mode default at the call site). String values are
      # constantized lazily so extensions may register by class name.
      #
      # @param key [Symbol, String]
      # @return [Object, nil]
      def provider(key)
        key = key.to_sym
        extensions.each_value do |ext|
          impl = ext[:providers][key]
          next if impl.nil?

          return impl.is_a?(String) ? impl.constantize : impl
        end
        nil
      end

      # --- Table-ownership seam (schema isolation) ---------------------------------
      # Extensions declare `owned_prefixes`; a table belongs to an extension iff its
      # name starts with "<prefix>_". PRIVATE extensions' prefixes drive the
      # public-schema dump exclusion (config/initializers/schema_dump_isolation.rb)
      # so committed public db/schema.rb never leaks private-extension
      # tables — the schema-layer twin of the public/private Gemfile split. Generic:
      # a new extension plugs in via register(owned_prefixes:), zero core edits.

      # True iff the named extension is private-by-location (extensions/private/*).
      def private?(slug)
        !!extensions.dig(slug.to_s, :private)
      end

      # All owned prefixes across every loaded extension (public + private).
      def all_owned_prefixes
        extensions.each_value.flat_map { |e| e[:owned_prefixes] || [] }.uniq
      end

      # Owned prefixes of PRIVATE extensions only — the dump-exclusion set.
      def private_table_prefixes
        extensions.each_value.select { |e| e[:private] }
                  .flat_map { |e| e[:owned_prefixes] || [] }.uniq
      end

      # True iff `table_name` is owned by a loaded private extension.
      def table_private?(table_name)
        name = table_name.to_s
        private_table_prefixes.any? { |p| name.start_with?("#{p}_") }
      end

      # Licensed availability of a feature for an account. Consults ONLY the features_module
      # of an extension that DECLARES the feature as a capability — so an unrelated extension
      # whose features_module returns a blanket value cannot affect the result. Returns the
      # owning extension's true/false decision, or false when no extension owns it.
      def feature_available?(feature, account: nil)
        cap = feature.to_sym
        extensions.each_value do |ext|
          next unless ext[:capabilities].include?(cap)

          mod = ext[:features_module]
          next unless mod&.respond_to?(:available?)

          result = mod.available?(feature, account: account)
          return result unless result.nil?
        end
        false
      end

      private

      def extensions
        @extensions ||= {}
      end
    end
  end
end
