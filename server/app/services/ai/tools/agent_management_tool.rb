# frozen_string_literal: true

module Ai
  module Tools
    class AgentManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      # === Per-action permission gating (G4 tail) ===
      #
      # REST twin: Ai::AgentHelpers#validate_permissions maps destroy ->
      # ai.agents.delete, create/clone -> ai.agents.create, update -> ai.agents.update,
      # and accepts ai.agents.execute ONLY for execute/test/pause/resume/archive.
      # The floor here is ai.agents.execute, so before this map an execute-only
      # holder could DELETE an agent (measured: Ai::Agent 1 -> 0).
      #
      # READ actions are deliberately LEFT ON THE FLOOR rather than mapped down
      # to their REST read permission. That leaves them stricter than REST,
      # which is safe; mapping them would LOOSEN a live surface, and this change
      # is scoped to closing an escalation, not to widening access.
      #
      # Keyed on the action that RUNS, never the invoked NAME — a user principal
      # is not pinned to the name (McpPlatformToolRegistrar#action_pinned_to_name?),
      # so a name-keyed check is bypassable via a sibling :action.
      ACTION_PERMISSIONS = {
        "create_agent" => "ai.agents.create",
        "update_agent" => "ai.agents.update",
        "delete_agent" => "ai.agents.delete",
        "set_agent_autonomy_level" => "ai.agents.update",
        "update_agent_trust_score" => "ai.agents.update"
      }.freeze


      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "check_task_status", mutating: false
      declare_action "create_agent", mutating: true
      declare_action "delete_agent", mutating: true
      declare_action "execute_agent", mutating: true
      declare_action "get_agent", mutating: false
      declare_action "list_agents", mutating: false
      declare_action "set_agent_autonomy_level", mutating: true
      declare_action "spawn_task", mutating: true
      declare_action "update_agent", mutating: true
      declare_action "update_agent_trust_score", mutating: true
      declare_action "wait_for_task", mutating: true

      def self.definition
        {
          name: "agent_management",
          description: "Create, list, get, update, or execute AI agents",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_agent, list_agents, get_agent, update_agent, execute_agent" },
            agent_id: { type: "string", required: false, description: "Agent ID (for execute)" },
            name: { type: "string", required: false, description: "Agent name (for create)" },
            description: { type: "string", required: false, description: "Agent description (for create)" },
            model: { type: "string", required: false, description: "Model name (for create)" },
            input: { type: "object", required: false, description: "Execution input (for execute)" },
            system_prompt: { type: "string", required: false, description: "System prompt (for create/update)" },
            conversation_profile: { type: "object", required: false, description: "Conversation profile (for create/update)" },
            status: { type: "string", required: false, description: "Agent status (for update)" }
          }
        }
      end

      def self.action_definitions
        {
          "create_agent" => {
            description: "Create a new AI agent with the specified configuration",
            parameters: {
              name: { type: "string", required: true, description: "Agent name" },
              description: { type: "string", required: false, description: "Agent description" },
              model: { type: "string", required: false, description: "Model name (defaults to provider default)" },
              agent_type: { type: "string", required: false, description: "Agent type (default: assistant)" },
              system_prompt: { type: "string", required: false, description: "System prompt" },
              conversation_profile: { type: "object", required: false, description: "Conversation profile configuration" }
            }
          },
          "list_agents" => {
            description: "List all active AI agents in the current account",
            parameters: {}
          },
          "get_agent" => {
            description: "Get detailed information about a specific AI agent",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or exact name" }
            }
          },
          "update_agent" => {
            description: "Update an existing AI agent's configuration",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or exact name" },
              name: { type: "string", required: false, description: "New agent name" },
              description: { type: "string", required: false, description: "New agent description" },
              status: { type: "string", required: false, description: "Agent status" },
              system_prompt: { type: "string", required: false, description: "System prompt" },
              conversation_profile: { type: "object", required: false, description: "Conversation profile configuration" },
              mcp_metadata: { type: "object", required: false, description: "MCP metadata to merge" }
            }
          },
          "set_agent_autonomy_level" => {
            description: "Manually set an agent's trust level (supervised/monitored/trusted/autonomous). Bypasses the computed trust_score tier. Use to bootstrap a new agent or override after manual review.",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or name" },
              trust_level: { type: "string", required: true, description: "supervised | monitored | trusted | autonomous" }
            }
          },
          "update_agent_trust_score" => {
            description: "Update an agent's computed AgentTrustScore record. Pass any subset of dimension scores (reliability/cost_efficiency/safety/quality/speed) or `overall_score` + `tier` to manually adjust. Auto-creates the trust_score row if missing.",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or name" },
              tier: { type: "string", required: false, description: "supervised | monitored | trusted | autonomous" },
              overall_score: { type: "number", required: false, description: "0.0–1.0" },
              reliability: { type: "number", required: false, description: "0.0–1.0" },
              cost_efficiency: { type: "number", required: false, description: "0.0–1.0" },
              safety: { type: "number", required: false, description: "0.0–1.0" },
              quality: { type: "number", required: false, description: "0.0–1.0" },
              speed: { type: "number", required: false, description: "0.0–1.0" }
            }
          },
          "delete_agent" => {
            description: "Hard-destroy an AI agent. Cascades children (executions/conversations/messages/skills/etc) via dependent:destroy. " \
                         "For FKs without dependent: (mcp_sessions, ralph_loops.default_agent_id, team memberships, telemetry, learnings, " \
                         "messages, a2a tasks, etc), if reassign_to_agent_id is given those rows are repointed to it; otherwise they are deleted. " \
                         "Irreversible.",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or name to destroy" },
              reassign_to_agent_id: { type: "string", required: false, description: "Agent UUID, slug, or name to repoint un-cascaded FKs to. If omitted, those rows are deleted." }
            }
          },
          "execute_agent" => {
            description: "Queue execution of a server-side AI agent (assistant type only). " \
                         "Cannot execute MCP client agents — use @mention in workspace messages to reach them.",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent ID, slug, or exact name" },
              input: { type: "object", required: false, description: "Execution input" }
            }
          },
          "spawn_task" => {
            description: "Spawn a task for another agent to execute. Validates capability matrix and delegation authority before dispatching.",
            parameters: {
              agent_id: { type: "string", required: true, description: "Target agent ID, slug, or name" },
              task: { type: "string", required: true, description: "Task description for the target agent" },
              budget_cents: { type: "integer", required: false, description: "Budget allocation in cents" }
            }
          },
          "check_task_status" => {
            description: "Check the status and output of a previously spawned task.",
            parameters: {
              task_id: { type: "string", required: true, description: "A2A task ID" }
            }
          },
          "wait_for_task" => {
            description: "Poll until a spawned task completes or times out.",
            parameters: {
              task_id: { type: "string", required: true, description: "A2A task ID" },
              timeout_seconds: { type: "integer", required: false, description: "Maximum wait time in seconds (default: 300)" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[AgentManagementTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "create_agent" then create_agent(params)
        when "list_agents" then list_agents
        when "get_agent" then get_agent(params)
        when "update_agent" then update_agent(params)
        when "set_agent_autonomy_level" then set_agent_autonomy_level(params)
        when "update_agent_trust_score" then update_agent_trust_score(params)
        when "delete_agent" then delete_agent(params)
        when "execute_agent" then execute_agent(params)
        when "spawn_task" then spawn_task(params)
        when "check_task_status" then check_task_status(params)
        when "wait_for_task" then wait_for_task(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      # FKs on ai_agents that have NO dependent:destroy on Ai::Agent and must be
      # explicitly handled before destroy. Reassign mode repoints these to the
      # canonical agent; delete mode deletes the rows.
      REASSIGN_AGENT_FKS = [
        ["mcp_sessions", "ai_agent_id"],
        ["ai_messages", "ai_agent_id"],
        ["ai_telemetry_events", "agent_id"],
        ["ai_compound_learnings", "source_agent_id"],
        ["ai_skill_usage_records", "ai_agent_id"],
        ["ai_skill_versions", "created_by_agent_id"],
        ["ai_skill_proposals", "proposed_by_agent_id"],
        ["ai_trajectories", "ai_agent_id"],
        ["ai_persistent_contexts", "ai_agent_id"],
        ["ai_context_entries", "ai_agent_id"],
        ["ai_context_access_logs", "ai_agent_id"],
        ["ai_experience_replays", "ai_agent_id"],
        ["ai_a2a_tasks", "from_agent_id"],
        ["ai_a2a_tasks", "to_agent_id"],
        ["ai_team_tasks", "assigned_agent_id"],
        ["chat_channels", "default_agent_id"],
        ["chat_sessions", "assigned_agent_id"],
        ["ai_task_reviews", "reviewer_agent_id"],
        ["ai_code_review_comments", "agent_id"],
        ["ai_skill_recipe_runs", "ai_agent_id"],
        ["ai_governance_reports", "monitor_agent_id"],
        ["ai_governance_reports", "subject_agent_id"],
        ["ai_stigmergic_signals", "emitter_agent_id"],
        ["ai_self_challenges", "challenger_agent_id"],
        ["ai_self_challenges", "executor_agent_id"],
        ["ai_self_challenges", "validator_agent_id"],
        ["ai_performance_benchmarks", "target_agent_id"],
        ["ai_test_scenarios", "target_agent_id"],
        ["community_agents", "agent_id"],
        ["ai_ralph_loops", "default_agent_id"],
        ["ai_agent_team_members", "ai_agent_id"]
      ].freeze

      # Rows that are operational/transient: only deleted when destroying a
      # dup agent, never repointed (no value to retain on the canonical).
      DELETE_AGENT_ROWS = [
        ["ai_deferred_operations", "ai_agent_id"],
        ["ai_agent_observations", "ai_agent_id"],
        ["ai_intervention_policies", "ai_agent_id"],
        ["ai_agent_proposals", "ai_agent_id"],
        ["ai_agent_escalations", "ai_agent_id"],
        ["ai_agent_feedbacks", "ai_agent_id"],
        ["ai_goal_plans", "ai_agent_id"],
        ["ai_team_restructure_events", "ai_agent_id"],
        ["ai_circuit_breakers", "agent_id"],
        ["ai_behavioral_fingerprints", "agent_id"],
        ["ai_delegation_policies", "agent_id"],
        ["ai_agent_cards", "ai_agent_id"]
      ].freeze

      private

      def create_agent(params)
        provider = account.ai_providers.where(is_active: true).first
        creator = user || account.users.first

        agent = account.ai_agents.create!(
          name: params[:name],
          description: params[:description],
          model: params[:model] || provider&.default_model || "claude-sonnet-4",
          status: "active",
          agent_type: params[:agent_type] || "assistant",
          creator: creator,
          provider: provider
        )
        { success: true, agent_id: agent.id, name: agent.name }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def list_agents
        agents = account.ai_agents.where(status: "active").limit(50)
        { success: true, agents: agents.map { |a| { id: a.id, name: a.name, model: a.model, status: a.status } } }
      end

      def execute_agent(params)
        identifier = params[:agent_id]
        agent = resolve_agent(identifier)
        return { success: false, error: "Agent not found for identifier: #{identifier}" } unless agent

        if agent.agent_type == "mcp_client"
          return {
            success: false,
            error: "Cannot execute MCP client agent '#{agent.name}'. " \
                   "MCP clients are external tools that cannot be executed server-side. " \
                   "To reach this agent, write '@#{agent.name}' in a workspace message instead."
          }
        end

        input_params = params[:input] || { "input" => "" }
        input_params = { "input" => input_params } if input_params.is_a?(String)
        input_params = input_params.stringify_keys if input_params.respond_to?(:stringify_keys)
        input_params = { "input" => "" } if input_params.blank?

        execution = Ai::AgentExecution.create!(
          account: account,
          agent: agent,
          user: user || account.users.first,
          provider: agent.using_account(account).resolved_provider || agent.provider,
          input_parameters: input_params,
          status: "pending",
          execution_id: SecureRandom.uuid,
          execution_context: { "source" => "mcp_tool", "triggered_at" => Time.current.iso8601 }
        )

        WorkerJobService.enqueue_ai_agent_execution(execution.id)

        { success: true, agent_id: agent.id, execution_id: execution.id, status: "execution_dispatched", message: "Agent execution dispatched to worker" }
      rescue WorkerJobService::WorkerServiceError => e
        { success: false, error: "Failed to dispatch execution: #{e.message}" }
      end

      def get_agent(params)
        agent_record = resolve_agent(params[:agent_id])
        return { success: false, error: "Agent not found" } unless agent_record
        {
          success: true,
          agent: {
            id: agent_record.id,
            name: agent_record.name,
            description: agent_record.description,
            status: agent_record.status,
            agent_type: agent_record.agent_type,
            model: agent_record.model,
            system_prompt: agent_record.system_prompt,
            conversation_profile: agent_record.conversation_profile,
            mcp_metadata: agent_record.mcp_metadata
          }
        }
      end

      def update_agent(params)
        agent_record = resolve_agent(params[:agent_id])
        raise ActiveRecord::RecordNotFound, "Agent not found" unless agent_record
        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:description] = params[:description] if params[:description].present?
        attrs[:status] = params[:status] if params[:status].present?
        attrs[:system_prompt] = params[:system_prompt] if params[:system_prompt].present?
        attrs[:conversation_profile] = params[:conversation_profile] if params[:conversation_profile].present?
        if params[:mcp_metadata].present?
          attrs[:mcp_metadata] = (agent_record.mcp_metadata || {}).merge(params[:mcp_metadata])
        end
        agent_record.update!(attrs)
        { success: true, agent_id: agent_record.id, name: agent_record.name }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Agent not found" }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      VALID_TRUST_LEVELS = %w[supervised monitored trusted autonomous].freeze

      def set_agent_autonomy_level(params)
        agent_record = resolve_agent(params[:agent_id])
        return { success: false, error: "Agent not found" } unless agent_record
        tl = params[:trust_level].to_s
        return { success: false, error: "trust_level must be one of #{VALID_TRUST_LEVELS.join('/')}" } unless VALID_TRUST_LEVELS.include?(tl)

        agent_record.update!(trust_level: tl)
        { success: true, agent_id: agent_record.id, trust_level: agent_record.trust_level }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def update_agent_trust_score(params)
        agent_record = resolve_agent(params[:agent_id])
        return { success: false, error: "Agent not found" } unless agent_record

        score = agent_record.trust_score || Ai::AgentTrustScore.new(
          account: account, agent: agent_record,
          reliability: 0.5, cost_efficiency: 0.5, safety: 0.5, quality: 0.5, speed: 0.5,
          overall_score: 0.5, tier: "supervised", evaluation_count: 0
        )

        attrs = {}
        %i[tier overall_score reliability cost_efficiency safety quality speed].each do |k|
          attrs[k] = params[k] if params.key?(k)
        end
        if attrs[:tier] && !VALID_TRUST_LEVELS.include?(attrs[:tier].to_s)
          return { success: false, error: "tier must be one of #{VALID_TRUST_LEVELS.join('/')}" }
        end

        score.assign_attributes(attrs)
        score.last_evaluated_at = Time.current
        score.save!

        { success: true, agent_id: agent_record.id, trust_score: {
          tier: score.tier, overall_score: score.overall_score,
          reliability: score.reliability, cost_efficiency: score.cost_efficiency,
          safety: score.safety, quality: score.quality, speed: score.speed,
          last_evaluated_at: score.last_evaluated_at&.iso8601
        } }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def delete_agent(params)
        agent_record = resolve_agent(params[:agent_id])
        return { success: false, error: "Agent not found" } unless agent_record

        canonical = nil
        if params[:reassign_to_agent_id].present?
          canonical = resolve_agent(params[:reassign_to_agent_id])
          return { success: false, error: "reassign_to_agent_id agent not found" } unless canonical
          return { success: false, error: "reassign_to_agent_id cannot equal agent_id" } if canonical.id == agent_record.id
        end

        repointed = Hash.new(0)
        deleted = Hash.new(0)
        name = agent_record.name
        agent_id = agent_record.id

        ActiveRecord::Base.transaction do
          REASSIGN_AGENT_FKS.each do |table, col|
            if canonical
              n = ActiveRecord::Base.connection.exec_update(
                "UPDATE #{table} SET #{col} = $1 WHERE #{col} = $2",
                "repoint-#{table}-#{col}", [canonical.id, agent_id]
              )
              repointed["#{table}.#{col}"] = n if n > 0
            else
              n = ActiveRecord::Base.connection.exec_delete(
                "DELETE FROM #{table} WHERE #{col} = $1",
                "del-#{table}-#{col}", [agent_id]
              )
              deleted["#{table}.#{col}"] = n if n > 0
            end
          end

          DELETE_AGENT_ROWS.each do |table, col|
            n = ActiveRecord::Base.connection.exec_delete(
              "DELETE FROM #{table} WHERE #{col} = $1",
              "del-#{table}-#{col}", [agent_id]
            )
            deleted["#{table}.#{col}"] = n if n > 0
          end

          agent_record.destroy!
        end

        {
          success: true, deleted: true, agent_id: agent_id, name: name,
          reassigned_to: canonical&.id, repointed_rows: repointed, deleted_rows: deleted
        }
      rescue ActiveRecord::InvalidForeignKey => e
        { success: false, error: "Foreign key blocks destroy — extend REASSIGN_AGENT_FKS or DELETE_AGENT_ROWS to cover it: #{e.message}" }
      rescue StandardError => e
        { success: false, error: "Failed to delete agent: #{e.class}: #{e.message}" }
      end

      def spawn_task(params)
        target = resolve_agent(params[:agent_id])
        return { success: false, error: "Target agent not found" } unless target

        # Validate capability matrix
        capability_service = Ai::Autonomy::CapabilityMatrixService.new(account: account)
        policy = capability_service.check(agent: target, action_type: "spawn_agent")
        if policy == :denied
          return { success: false, error: "Agent #{target.name} is not permitted to receive spawned tasks (tier: #{target.trust_level || 'supervised'})" }
        end

        # Validate delegation authority if spawning agent is known
        if agent&.id.present?
          spawner = ::Ai::Agent.for_account(account.id).find_by(id: agent.id)
          if spawner
            delegation_service = Ai::Autonomy::DelegationAuthorityService.new(account: account)
            delegation = delegation_service.validate_delegation(
              delegator: spawner, delegate: target,
              task: { action_type: "execute", budget_cents: params[:budget_cents].to_i }
            )
            unless delegation[:allowed]
              return { success: false, error: "Delegation denied: #{delegation[:reason]}" }
            end
          end
        end

        # Submit A2A task — resolve agent card for the target agent
        agent_card = target.agent_card || target.create_agent_card!(
          account: account, name: target.name, description: target.description,
          endpoint_url: nil, status: "active"
        )
        a2a_service = Ai::A2a::Service.new(account: account, user: user || account.users.first)
        task = a2a_service.submit_task(
          to_agent_card: agent_card.id,
          message: { role: "user", parts: [{ type: "text", text: params[:task] }] },
          metadata: { source: "spawn_task", budget_cents: params[:budget_cents] }
        )

        { success: true, task_id: task.task_id, status: task.status, agent_id: target.id, agent_name: target.name }
      rescue StandardError => e
        { success: false, error: "Failed to spawn task: #{e.message}" }
      end

      def check_task_status(params)
        task = account.ai_a2a_tasks.find_by(task_id: params[:task_id])
        return { success: false, error: "Task not found" } unless task

        {
          success: true,
          task_id: task.task_id,
          status: task.status,
          output: task.output,
          error_message: task.error_message,
          duration_ms: task.duration_ms,
          created_at: task.created_at.iso8601,
          completed_at: task.completed_at&.iso8601
        }
      end

      def wait_for_task(params)
        task_id = params[:task_id]
        timeout = [params[:timeout_seconds].to_i, 300].min
        timeout = 300 if timeout <= 0
        deadline = Time.current + timeout.seconds

        loop do
          task = account.ai_a2a_tasks.find_by(task_id: task_id)
          return { success: false, error: "Task not found" } unless task

          if %w[completed failed cancelled].include?(task.status)
            return {
              success: true,
              task_id: task.task_id,
              status: task.status,
              output: task.output,
              error_message: task.error_message,
              duration_ms: task.duration_ms
            }
          end

          if Time.current >= deadline
            return { success: false, error: "Timeout waiting for task #{task_id}", status: task.status }
          end

          sleep 2
        end
      end

      # Flexible agent lookup: try UUID, then slug, then name match
      def resolve_agent(identifier)
        return nil if identifier.blank?

        ::Ai::Agent.for_account(account.id).find_by(id: identifier) ||
          account.ai_agents.find_by(slug: identifier) ||
          account.ai_agents.find_by(name: identifier)
      end

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder: in-process
      # callers that opted in with `internal: true`, and an mTLS node principal
      # whose specific tool name already cleared Mcp::Principal#may_invoke?.
      # Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

    end
  end
end
