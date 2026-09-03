# frozen_string_literal: true

module Ai
  module ClaudeExport
    # Which DOMAIN owns an intervention-policy category ("system.sdwan_create_peer"
    # -> "sdwan"). Used to derive an agent's policy domains for its Claude Code
    # routing description and for the router's domain dimension.
    #
    # CORE-PURE SEAM. The authoritative prefix table lives in the extension that
    # owns the categories (the system extension's autonomy domain pivot); core
    # must not name it (Extension Isolation), so an extension REGISTERS its map
    # here at boot — first match wins, in registration order, exactly like that
    # pivot — and core falls back to a generic heuristic (the leading family
    # token after the namespace) for anything unregistered. The heuristic is
    # deliberately coarse: "system.instance_pool_replenish" reads as "instance"
    # until the owning extension registers "instance_pool"; a coarse domain
    # name is still a true routing trigger, a wrong one would not be.
    module PolicyDomains
      NAMESPACE_PREFIX = "system."

      module_function

      # @param domain   [String] domain name, e.g. "sdwan"
      # @param prefixes [Array<String>] category prefixes owned by that domain
      def register(domain, prefixes)
        registered << [ domain.to_s, Array(prefixes).map(&:to_s) ]
        nil
      end

      def registered
        @registered ||= []
      end

      # Spec seam: forget every registration.
      def reset!
        @registered = []
      end

      # @return [String, nil] nil for blank/wildcard categories
      def domain_for(category)
        name = category.to_s.strip
        return nil if name.empty?

        registered.each do |(domain, prefixes)|
          return domain if prefixes.any? { |prefix| name.start_with?(prefix) }
        end

        heuristic(name)
      end

      def for_categories(categories)
        Array(categories).filter_map { |category| domain_for(category) }.uniq
      end

      def heuristic(name)
        rest = name.start_with?(NAMESPACE_PREFIX) ? name.delete_prefix(NAMESPACE_PREFIX) : name
        token = rest.split(/[._]/).first.to_s
        token.match?(/\A[a-z][a-z0-9]*\z/) ? token : nil
      end
    end
  end
end
