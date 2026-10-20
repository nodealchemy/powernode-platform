# frozen_string_literal: true

module Ai
  module Tools
    # platform.assemble_task — the MCP face of Ai::Assembly::Service
    # (skills-first agents, PRE-2): "which skills, learnings, tier, model and
    # effort does this task need, for this agent?" A Claude Code session calls it
    # BEFORE spawning a powernode/* subagent (passing the returned model/effort to
    # the Agent tool and the assembly_id in the prompt); the spawned subagent
    # calls it with that assembly_id and gets the stored assembly back.
    #
    # In the bootstrap floor (Ai::Tools::BootstrapVerbs): every agent and every
    # thin loader has it. Declared `mutating: false` because it acts on no
    # platform resource — its only write is its own assembly record, a row on
    # ai_routing_decisions (request_type "task_assembly"; one per fresh call, a
    # fetch by assembly_id writes none). It is NOT a routing choice, so the
    # routing analytics exclude it (Ai::RoutingDecision.excluding_assemblies).
    # route_task, by contrast, persists nothing. The honest annotation would be
    # "writes only its own record"; readOnlyHint is true so the verb can sit in
    # the bootstrap floor. Read-gated on ai.agents.read.
    class AssemblyTool < BaseTool
      tool_family "agents"

      REQUIRED_PERMISSION = "ai.agents.read"

      declare_action "assemble_task", mutating: false,
                     returns: "assembly_id, skills[] (slug, name, system_prompt, manifest, score), learnings[], " \
                              "knowledge_tags[], tier, model (claude_code context only), effort, floor_reason, " \
                              "uncovered[] and routing_decision_id; with assembly_id, the stored assembly unchanged",
                     refuses: [ "agent_slug is not a roster agent", "task is blank and no assembly_id is given",
                                "assembly_id names no assembly of this account", "context is not claude_code or platform" ],
                     see_also: { "route_task" => "ranking the platform agent for a task", "record_agent_execution" => "reporting the run (pass assembly_id)" }

      def self.definition
        {
          name: "assemble_task",
          description: "Assemble a task for a platform agent: the skills that own it (domain-ceilinged, at most five, " \
                       "with their prompts and verb manifests), the learnings those skills carry, and the tier, " \
                       "model and effort to run at (context claude_code: model is haiku|sonnet|opus|fable, effort is " \
                       "the Agent tool's). Persists the assembly and returns its assembly_id; call again with the " \
                       "assembly_id to fetch it unchanged.",
          parameters: {
            action: { type: "string", required: false, description: "assemble_task" },
            task: { type: "string", required: false, description: "The task, in natural language (required unless assembly_id is given)" },
            agent_slug: { type: "string", required: false, description: "The roster agent that will run it (required unless assembly_id is given)" },
            context: { type: "string", required: false, enum: Ai::Assembly::Service::CONTEXTS, description: "claude_code (default) or platform" },
            lane: { type: "string", required: false, description: "Optional lane or signal reference, stored with the assembly" },
            assembly_id: { type: "string", required: false, description: "Fetch the stored assembly instead of assembling" }
          }
        }
      end

      def self.action_definitions
        {
          "assemble_task" => {
            description: definition[:description],
            parameters: definition[:parameters].except(:action),
            examples: [
              { description: "Assemble before spawning the engineer from Claude Code",
                params: { task: "Work a dev-improve task that adds a migration and a spec", agent_slug: "platform-engineer", context: "claude_code" } },
              { description: "A spawned subagent fetches what its session assembled",
                params: { agent_slug: "platform-engineer", assembly_id: "<assembly_id from the prompt>" } }
            ]
          }
        }
      end

      def call(params)
        unless action_permitted?
          Rails.logger.warn("[AssemblyTool] Refused assemble_task: #{REQUIRED_PERMISSION} required user=#{user&.id}")
          return error_result("permission denied: #{REQUIRED_PERMISSION} required")
        end

        result = ::Ai::Assembly::Service.new(account: account).call(
          task: params[:task], agent_slug: params[:agent_slug], context: params[:context].presence || "claude_code",
          lane: params[:lane].presence, assembly_id: params[:assembly_id].presence
        )
        success_result(result)
      rescue ::Ai::Assembly::Service::Refusal => e
        error_result(e.message)
      rescue StandardError => e
        rescued_error_result(e, message: "assembly failed")
      end

      private

      def action_permitted?
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(REQUIRED_PERMISSION) == true
      end
    end
  end
end
