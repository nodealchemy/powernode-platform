# frozen_string_literal: true

module Ai
  module ClaudeExport
    # THE ONE PLACE that maps a platform agent's tool access to the Claude Code
    # `tools:` frontmatter allowlist (HIER-P1B item 3).
    #
    # Resolution mirrors AgentToolBridgeService (#platform_tool_definitions +
    # #scope_to_tool_families), in the same order, so the CC counterpart of an
    # agent sees the same platform surface the platform's own executor would
    # hand it:
    #   1. tool_access.enabled == false          -> bootstrap verbs only (which
    #                                              since HIER-P1C include the
    #                                              self-report verb: it writes
    #                                              only this run's own history
    #                                              row, so the kill switch still
    #                                              denies every acting verb)
    #   2. tool_access.allowed_tools (not ["*"]) -> exactly those (registered) names
    #   3. tool_access.full_registry == true     -> UNSCOPED (nil: omit `tools:`,
    #                                              CC inherits every tool)
    #   4. tool_access.tool_families             -> registry names matching a
    #      / SiteSetting per-type family defaults   family exactly or by `<family>_`
    #                                              prefix; NO match fails open to
    #                                              unscoped (the bridge's rule:
    #                                              misconfiguration must not disarm)
    #   5. nothing configured                    -> the platform READ verbs only
    #      (this is where the export is STRICTER than the bridge, which serves the
    #      full registry — a committed CC allowlist errs on the side of read-only)
    #
    # Every skeleton always carries the bootstrap verbs — Ai::Tools::
    # BootstrapVerbs::ACTIONS, THE ONE read-only set shared with the runtime
    # bridge since HIER-P2H (get_agent so the file can fetch its own prompt,
    # plus the discovery/knowledge/routing verbs BASE_GUARDRAILS orders every
    # agent to call), the self-report verb (record_agent_execution — HIER-P1C:
    # the body's final step reports the run back so the platform's statistics
    # see it; the verb records history and is not autonomy-gated, but it IS a
    # write, so it lives beside the shared read-only set rather than in it),
    # and the CC built-ins its agent type needs: Read/Grep/Glob for every
    # agent; Edit/Write/Bash only for code_assistant.
    #
    # Registered action names come from the registry's own surface
    # (PlatformApiToolRegistry.all_tools), never a literal list; a READ verb is
    # one whose BaseTool declaration says `mutating: false` under the name that
    # actually dispatches (McpPlatformToolRegistrar::ACTION_ALIASES). An
    # undeclared action is treated as mutating — conservative by construction.
    module ToolAllowlist
      MCP_PREFIX = "mcp__powernode__platform_"
      BASE_BUILTINS = %w[Read Grep Glob].freeze
      CODE_BUILTINS = %w[Edit Write Bash].freeze
      CODE_AGENT_TYPES = %w[code_assistant].freeze
      SELF_REPORT_ACTIONS = %w[record_agent_execution].freeze
      BOOTSTRAP_ACTIONS = (::Ai::Tools::BootstrapVerbs::ACTIONS + SELF_REPORT_ACTIONS).freeze
      UNSCOPED = :all

      # One walk of the registry per export run (~600 constantize + declaration
      # lookups), reused across every agent rendered in that run.
      class Registry
        def self.snapshot
          new
        end

        def action_names
          @action_names ||= ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)
        end

        def read_action_names
          @read_action_names ||= ::Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |name, class_name|
            klass = class_name.constantize
            dispatched = ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(name, name)
            declaration = klass.declared_actions[dispatched.to_s]
            name.to_s if declaration && declaration[:mutating] == false
          rescue NameError
            nil
          end
        end

        def registered?(name)
          action_names.include?(name.to_s)
        end
      end

      module_function

      # @return [Array<String>, nil] the `tools:` entries, or nil when the agent
      #   is unscoped (omit the key so CC inherits everything)
      def for(agent, registry: Registry.snapshot)
        actions = platform_actions_for(agent, registry: registry)
        return nil if actions == UNSCOPED

        builtins_for(agent) + (BOOTSTRAP_ACTIONS | actions).map { |action| mcp_name(action) }
      end

      def builtins_for(agent)
        CODE_AGENT_TYPES.include?(agent.agent_type.to_s) ? BASE_BUILTINS + CODE_BUILTINS : BASE_BUILTINS
      end

      def mcp_name(action)
        "#{MCP_PREFIX}#{action}"
      end

      # @return [Array<String>, UNSCOPED] registered platform action names
      def platform_actions_for(agent, registry: Registry.snapshot)
        config = tool_access_config(agent)
        return [] if config.key?("enabled") && config["enabled"] != true

        allowed = config["allowed_tools"]
        if allowed.present?
          return UNSCOPED if Array(allowed) == [ "*" ]

          return Array(allowed).map(&:to_s).select { |name| registry.registered?(name) }
        end

        return UNSCOPED if config["full_registry"] == true

        families = families_for(agent, config)
        return registry.read_action_names if families.blank?

        scoped = registry.action_names.select { |name| in_families?(name, families) }
        scoped.empty? ? UNSCOPED : scoped
      end

      def tool_access_config(agent)
        config = agent.mcp_metadata.is_a?(Hash) ? agent.mcp_metadata["tool_access"] : nil
        config.is_a?(Hash) ? config : {}
      end

      # Same two sources, same precedence, as AgentToolBridgeService#tool_families.
      def families_for(agent, config)
        configured = config["tool_families"]
        return Array(configured).map(&:to_s) if configured.present?

        defaults = SiteSetting.get(::Ai::AgentToolBridgeService::FAMILY_DEFAULTS_SETTING)
        return nil unless defaults.is_a?(Hash)

        family_list = defaults[agent.agent_type.to_s]
        family_list.present? ? Array(family_list).map(&:to_s) : nil
      rescue StandardError => e
        Rails.logger.warn "[ClaudeExport::ToolAllowlist] Tool-family defaults lookup failed: #{e.message}"
        nil
      end

      def in_families?(name, families)
        families.any? { |family| name == family || name.start_with?("#{family}_") }
      end
    end
  end
end
