# frozen_string_literal: true

module Ai
  module Tools
    # platform.route_task — the MCP face of Ai::Routing::AgentRouterService
    # (HIER-P1B item 10): "which platform agent should handle this task?", with
    # the ranked candidates, the reason behind each score, and the winner's
    # Claude Code `subagent_type` slug so the caller can `Agent()` it directly.
    # Read-only: it ranks, it never executes or delegates.
    #
    # The candidate set is Ai::Routing::RoutableAgents — the same set the
    # committed .claude/agents/powernode/ skeletons carry — so a slug returned
    # here always names a spawnable subagent on a checkout with fresh skeletons.
    class AgentRoutingTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      declare_action "route_task", mutating: false

      def self.definition
        {
          name: "route_task",
          description: "Route a task description to the best platform agent: ranked candidates with per-dimension " \
                       "reasons (capability, trust, skill match, policy domain, tier/cost, performance) and the " \
                       "winner's Claude Code subagent_type slug. Honours the delegator's delegation policy. Read-only.",
          parameters: {
            action: { type: "string", required: false, description: "route_task" },
            task_description: { type: "string", required: false,
                                description: "The task to route (natural language). Required." },
            constraints: {
              type: "object", required: false,
              description: "Optional: delegator_agent_id or delegator_slug (the asking agent — its delegation " \
                           "policy binds the result and it is never a candidate), agent_type (restrict to one " \
                           "type), limit (candidates returned, 1-#{::Ai::Routing::AgentRouterService::MAX_LIMIT}, " \
                           "default #{::Ai::Routing::AgentRouterService::DEFAULT_LIMIT})"
            }
          }
        }
      end

      def self.action_definitions
        {
          "route_task" => {
            description: definition[:description],
            parameters: {
              task_description: { type: "string", required: true, description: "The task to route (natural language)" },
              constraints: definition[:parameters][:constraints]
            },
            examples: [
              { description: "Find the specialist for an SD-WAN change",
                params: { task_description: "attach a new sdwan peer and refresh the route policies" } },
              { description: "Route on behalf of the concierge, honouring its delegation policy",
                params: { task_description: "triage the new critical CVE",
                          constraints: { delegator_slug: "system-concierge", limit: 3 } } }
            ]
          }
        }
      end

      def call(params)
        unless action_permitted?
          Rails.logger.warn("[AgentRoutingTool] Refused route_task: #{REQUIRED_PERMISSION} required user=#{user&.id}")
          return error_result("permission denied: #{REQUIRED_PERMISSION} required")
        end

        task = params[:task_description].to_s.strip
        return error_result("task_description is required") if task.empty?

        constraints = normalize(params[:constraints])
        delegator = resolve_delegator(constraints)
        return error_result("delegator not found") if delegator_requested?(constraints) && delegator.nil?

        candidates = ::Ai::Routing::RoutableAgents.for(account.id)
        if constraints["agent_type"].present?
          wanted = constraints["agent_type"].to_s.downcase.strip
          candidates = candidates.select { |agent| agent.agent_type == wanted }
        end

        routed = ::Ai::Routing::AgentRouterService.new(account: account).route(
          task: task, delegator: delegator, candidates: candidates,
          limit: constraints.fetch("limit", ::Ai::Routing::AgentRouterService::DEFAULT_LIMIT)
        )

        success_result(
          subagent_type: routed[:subagent_type],
          winner: routed[:candidates].first,
          candidates: routed[:candidates],
          complexity: routed[:complexity],
          delegation: routed[:delegation],
          reasoning: routed[:reasoning],
          spawn_hint: routed[:subagent_type] && %(Agent(subagent_type: "#{routed[:subagent_type]}", prompt: <the task>)),
          agent_id: routed[:agent_id],
          agent_name: routed[:agent_name],
          confidence: routed[:confidence]
        )
      rescue StandardError => e
        Rails.logger.error("[AgentRoutingTool] route_task failed: #{e.class}: #{e.message}")
        error_result("routing failed: #{e.message}")
      end

      private

      def normalize(constraints)
        hash = constraints.respond_to?(:to_unsafe_h) ? constraints.to_unsafe_h : constraints
        hash.is_a?(Hash) ? hash.transform_keys(&:to_s) : {}
      end

      def delegator_requested?(constraints)
        constraints["delegator_agent_id"].present? || constraints["delegator_slug"].present?
      end

      def resolve_delegator(constraints)
        if constraints["delegator_agent_id"].present?
          ::Ai::Agent.for_account(account.id).find_by(id: constraints["delegator_agent_id"].to_s)
        elsif constraints["delegator_slug"].present?
          ::Ai::Agent.resolve_for(account.id, slug: constraints["delegator_slug"].to_s)
        end
      end

      # Same two bypasses as the sibling tools' ladder (in-process `internal:
      # true` callers; an mTLS instance principal that already cleared its
      # per-tool grant), then the read floor against the user.
      def action_permitted?
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(REQUIRED_PERMISSION) == true
      end
    end
  end
end
