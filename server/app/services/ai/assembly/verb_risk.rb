# frozen_string_literal: true

module Ai
  module Assembly
    # Which of a skill's manifest verbs are GATED: a destroy-shaped verb, or one
    # whose declare_action can park for approval (Ai::Tools::BaseTool.may_park?).
    # Read from the registry's own declarations under the name that actually
    # dispatches (McpPlatformToolRegistrar::ACTION_ALIASES), never from a name
    # pattern, so a newly gated verb raises the tier with no edit here. A name
    # the registry does not know (an extension that is not loaded) is not gated:
    # it cannot be called either.
    #
    # PARKING vs DESTRUCTIVE. A verb that merely CAN park (an approval-gated
    # probe such as an on-node inspection, governed auto_approve by default) is
    # not a mutation of the fleet, and a read-only skill (manifest.gate_category
    # "read", checked by the contract against read_only) may use it without
    # raising its tier. So the caller passes `parking: false` for such a skill:
    # only destroy-shaped verbs then count. Every other skill counts both.
    class VerbRisk
      # @param names [Array<String>] manifest verb names
      # @param parking [Boolean] count verbs that can park for approval (not only destructive ones)
      # @return [Array<String>] the gated ones, in the order given
      def gated_verbs(names, parking: true)
        Array(names).map(&:to_s).uniq.select { |name| gated?(name, parking: parking) }
      end

      def gated?(name, parking: true)
        declaration, tool = declaration_for(name)
        return false unless declaration

        declaration[:destructive] == true || (parking && tool.may_park?(declaration))
      end

      private

      def declaration_for(name)
        class_name = registry[name]
        return nil unless class_name

        tool = class_name.is_a?(String) ? class_name.safe_constantize : class_name
        return nil unless tool.respond_to?(:declared_action)

        dispatched = ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(name, name)
        [ tool.declared_action(dispatched), tool ]
      end

      def registry
        @registry ||= ::Ai::Tools::PlatformApiToolRegistry.all_tools
      end
    end
  end
end
