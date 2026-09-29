# frozen_string_literal: true

module Ai
  module DevMerge
    # The private-extension names dev_merge_increment may never publish (in a
    # landed commit, a generated message or a caller's summary), and whether
    # this host can KNOW them.
    #
    # WHY THREE SOURCES. The core-purity gate derives the names from the
    # directories under extensions/private/, which exist on a maintainer's
    # checkout. The deployed control plane runs from a module composed without
    # them, so on the host where this verb actually runs that directory is
    # absent and the derivation alone answers [] — the "absence looks clean"
    # shape, with every refusal inert. So the answer is the union of:
    #
    #   1. Shared::ExtensionPaths.private_slugs — extensions/private/* on disk;
    #   2. Powernode::ExtensionRegistry — every LOADED engine the registry marks
    #      private (private-by-location, derived at registration, never
    #      hardcoded), which covers a node that composes a private extension;
    #   3. the operator's declaration, SiteSetting SETTING_KEY: a JSON list of
    #      the private extensions that exist in this deployment's ecosystem
    #      but are not installed here. Registered PROTECTED (see
    #      config/initializers/dev_merge_settings.rb), so shrinking it — which
    #      disarms the refusal — is a person's decision in their own session.
    #
    # FAIL CLOSED. The union is a determinate answer only when this host can
    # know it is COMPLETE:
    #   * the operator declared the list, even as [];
    #   * the platform is in core mode (no extension registered at all:
    #     Shared::FeatureGateService.core_mode?); or
    #   * extensions/private/ exists on disk (a checkout that carries the
    #     private extensions, the core-purity gate's own source).
    # A registry-only list is NOT enough (review N1): a loaded private engine
    # proves that some private extension is installed here, never that it is
    # the only one. Otherwise this host cannot tell "these are all of them"
    # from "others exist but are not installed here", and the merge is refused
    # with #reason.
    #
    # The names are never logged or audited; #reason never contains one.
    class ForbiddenNames
      SETTING_KEY = "dev_merge.private_extension_names"
      SLUG = /\A[a-z0-9][a-z0-9_-]*\z/

      Result = Struct.new(:names, :determinate, :reason, keyword_init: true) do
        def determinate?
          determinate == true
        end
      end

      def self.resolve
        declared = declared_names
        names = (::Shared::ExtensionPaths.private_slugs + registered_private + Array(declared)).map(&:to_s).uniq.sort

        if !declared.nil? || ::Shared::FeatureGateService.core_mode? || ::Shared::ExtensionPaths.private_root_present?
          return Result.new(names: names, determinate: true)
        end

        Result.new(names: [], determinate: false, reason: indeterminate_reason)
      end

      # nil when the operator has not declared a list; the declared list
      # (possibly empty) otherwise. A malformed value counts as undeclared,
      # never as "none".
      def self.declared_names
        value = ::SiteSetting.get(SETTING_KEY)
        value.is_a?(Array) && value.all? { |v| v.is_a?(String) && v.match?(SLUG) } ? value : nil
      end

      def self.registered_private
        ::Powernode::ExtensionRegistry.all.filter_map { |slug, ext| slug.to_s if ext.is_a?(Hash) && ext[:private] }
      end

      # The SiteSetting value check (config/initializers/dev_merge_settings.rb).
      def self.declaration_problem(value)
        parsed = value.is_a?(String) ? JSON.parse(value) : value
        return nil if parsed.is_a?(Array) && parsed.all? { |v| v.is_a?(String) && v.match?(SLUG) }

        "must be a JSON list of extension slugs (lowercase letters, digits, - and _)"
      rescue JSON::ParserError
        "must be a JSON list of extension slugs (lowercase letters, digits, - and _)"
      end

      def self.indeterminate_reason
        "this host cannot tell which private extensions exist (it has no extensions/private/ directory and " \
          "none was declared), " \
          "so it cannot refuse their names; refusing to publish. Declare them in the protected site setting " \
          "#{SETTING_KEY} (a JSON list; [] declares that none exist)"
      end
    end
  end
end
