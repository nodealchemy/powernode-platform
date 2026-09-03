# frozen_string_literal: true

module Ai
  module Tools
    class AgentAutonomyTool < BaseTool
      # SECURITY (IMP-e8adfcfcab9b): authorization here is per ACTION, not per
      # tool. REQUIRED_PERMISSION was inherited as nil from BaseTool, and
      # McpPlatformToolRegistrar#enforce_permission! opens with
      # `return if required.nil?` — ABOVE the authentication raise and the
      # has_permission? raise. Every action on this tool was therefore
      # reachable by any MCP caller with no check at all,
      # including approve_deferred_operation, which EXECUTES the approved
      # operation while its REST twin requires ai.autonomy.approve.
      #
      # No single constant can fix that. This tool bundles reads, goal writes,
      # policy CRUD and approvals, whose REST twins require four different
      # permissions: a constant tight enough for approval locks callers out of
      # goals, and one loose enough for goals leaves approval under-gated while
      # looking gated. So the constant is the FLOOR — the least-privileged
      # action's twin, and what the registrar enforces for the whole tool — and
      # ACTION_PERMISSIONS raises it per action to exactly what the REST surface
      # for the same operation demands. This is the same shape seven sibling
      # tools already use (SystemFleetTool, SdwanTool, SystemStorageOwnerTool
      # and friends); per-action gating is not expressible in the registrar
      # itself, whose enforce_permission! runs BEFORE the action is resolved.
      #
      # Floor: Api::V1::Ai::AutonomyController#validate_permissions gates every
      # read on the autonomy surface (approvals queue included) on this.
      REQUIRED_PERMISSION = "ai.agents.read"

      # Each entry names the permission the REST twin of that action requires.
      # Actions ABSENT here are deliberately at the floor: the agent-voice
      # actions (escalate, report_issue, propose_feature, create_proposal,
      # request_feedback, send_proactive_notification, discover_claude_sessions)
      # have no twin at all — the proposals and escalations controllers expose
      # only index/show plus review/resolve, and no human surface CREATES
      # either one — so
      # the parity invariant says nothing about them, and tightening them would
      # cut off an agent's route to a human.
      ACTION_PERMISSIONS = {
        # POST /api/v1/ai/autonomy/approvals/:id/{approve,reject}
        #   → Ai::AutonomyApprovalActions#require_approval_permission.
        # approve_deferred_operation EXECUTES the operation — the reported hole.
        "approve_deferred_operation" => "ai.autonomy.approve",
        "reject_deferred_operation" => "ai.autonomy.approve",

        # Api::V1::Ai::InterventionPoliciesController#validate_permissions —
        # blanket, so the read is gated exactly like the writes.
        "list_intervention_policies" => "ai.intervention_policies.manage",
        "create_intervention_policy" => "ai.intervention_policies.manage",
        "update_intervention_policy" => "ai.intervention_policies.manage",
        "delete_intervention_policy" => "ai.intervention_policies.manage",

        # Api::V1::Ai::GoalsController / GoalPlansController#validate_permissions
        # — also blanket. decompose_goal writes to a goal's plan, so it follows
        # the goal surface rather than the approvals one.
        #
        # validate_plan / approve_plan used to sit here too. They were
        # unregistered (IMP-4707960fc610): both bodies constantized
        # Ai::Autonomy::PlanValidationService / PlanApprovalService, which exist
        # in neither core nor any extension, so behind a `rescue NameError` the
        # only behaviour either verb ever had was "service not available".
        # spec/services/ai/tools/tool_constant_resolution_spec.rb now fails on
        # that shape rather than letting it be advertised.
        "create_agent_goal" => "ai.goals.manage",
        "list_agent_goals" => "ai.goals.manage",
        "update_agent_goal" => "ai.goals.manage",
        "decompose_goal" => "ai.goals.manage",

        # NOT an agent-voice action, despite sitting among them: it writes an
        # assistant message into an existing workspace conversation
        # (conversation.messages.create!), which is what Ai::Tools::ConversationTool
        # does under REQUIRED_PERMISSION = "ai.conversations.create". Its twin is
        # therefore on the MCP surface rather than REST, and the invariant holds
        # just the same — leaving it at the floor would let a caller write into a
        # conversation through this tool that platform.send_message refuses.
        "request_code_change" => "ai.conversations.create",

        # HIER-P0 — set_delegation_policy PROPOSES an agent's delegation
        # authority; the write itself lands only after Ai::AutonomyGate
        # (category ai.delegation_policy.update, default require_approval)
        # lets it through. Operator ruling: ai.agents.update, the agent-update
        # permission, rather than ai.autonomy.manage (what the REST twins
        # create/update_delegation_policy demand): the REST verbs WRITE the
        # row directly, while this verb only parks a proposal — and a caller
        # who may edit an agent may propose its delegation policy. The read
        # (describe_delegation) stays at the floor: its twin, GET
        # /api/v1/ai/autonomy/delegation_policies/:agent_id, is gated on
        # ai.agents.read by AutonomyController#validate_permissions.
        #
        # This entry prices the SELF case only. A proposal naming another agent
        # is charged CROSS_AGENT_DELEGATION_PERMISSION in #effective_perm_for —
        # see the comment there.
        "set_delegation_policy" => "ai.agents.update"

        # list_deferred_operations stays at the floor on purpose: its twin is
        # GET /api/v1/ai/autonomy/approvals, which validate_permissions gates on
        # ai.agents.read. agent_introspect likewise.
      }.freeze

      # Advertisement is deliberately NOT narrowed by the floor. BaseTool's
      # default short-circuits on a nil REQUIRED_PERMISSION, so setting one
      # would newly make this tool's presence in an agent's toolset depend on
      # an account-wide "does ANY user hold ai.agents.read?" query — and in an
      # account where none does, the whole surface would silently vanish from
      # the agent, including escalate and report_issue, which are its route to
      # a human. An agent that cannot execute the action should get a refusal
      # it can report, not a capability that was never offered. Execution stays
      # gated by the registrar's floor and by ACTION_PERMISSIONS; only
      # visibility is restored to what it was before that constant existed.
      # Same override, and the same reason, as Ai::Tools::KillSwitchTool.
      def self.permitted?(agent:)
        true
      end

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "agent_introspect", mutating: false
      declare_action "approve_deferred_operation", mutating: true
      declare_action "create_agent_goal", mutating: true
      declare_action "create_intervention_policy", mutating: true
      declare_action "create_proposal", mutating: true
      declare_action "decompose_goal", mutating: true
      declare_action "delete_intervention_policy", mutating: true
      declare_action "discover_claude_sessions", mutating: false
      declare_action "escalate", mutating: true
      declare_action "list_agent_goals", mutating: false
      declare_action "list_deferred_operations", mutating: false
      declare_action "list_intervention_policies", mutating: false
      declare_action "propose_feature", mutating: true
      declare_action "reject_deferred_operation", mutating: true
      declare_action "report_issue", mutating: true
      declare_action "request_code_change", mutating: true
      declare_action "request_feedback", mutating: true
      declare_action "send_proactive_notification", mutating: true
      declare_action "update_agent_goal", mutating: true
      declare_action "update_intervention_policy", mutating: true

      # HIER-P0 — delegation authority. The read is plain; the write is the
      # first action on this tool wired to the gate through the generic
      # DeferredToolCall replay seam (BaseTool#deferred_tool_call_context /
      # #deferred_tool_call_result), so an approved proposal is replayed as
      # the ORIGINAL caller and the action body below runs only on that
      # replay (or on an operator's explicit auto_approve policy).
      declare_action "describe_delegation", mutating: false
      declare_action "set_delegation_policy",
                     mutating: true,
                     action_category: "ai.delegation_policy.update",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      def self.definition
        {
          name: "agent_autonomy",
          description: "Agent autonomy tools: goals, proposals, escalations, introspection, proactive notifications, and code change requests",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_agent_goal, list_agent_goals, update_agent_goal, agent_introspect, propose_feature, send_proactive_notification, discover_claude_sessions, request_code_change, create_proposal, escalate, request_feedback, report_issue, describe_delegation, set_delegation_policy" }
          }
        }
      end

      def self.action_definitions
        {
          "create_agent_goal" => {
            description: "Create a goal for an agent (self or managed)",
            parameters: {
              agent_id: { type: "string", description: "Target agent ID (omit for self)", required: false },
              title: { type: "string", description: "Goal title", required: true },
              description: { type: "string", description: "Goal description", required: false },
              goal_type: { type: "string", description: "maintenance, improvement, creation, monitoring, feature_suggestion, reaction", required: true },
              priority: { type: "integer", description: "1 (highest) to 5 (lowest), default 3", required: false },
              parent_goal_id: { type: "string", description: "Parent goal ID for sub-goals", required: false },
              success_criteria: { type: "object", description: "Machine-evaluable success criteria", required: false }
            }
          },
          "list_agent_goals" => {
            description: "List an agent's goals (introspection)",
            parameters: {
              agent_id: { type: "string", description: "Target agent ID (omit for self)", required: false },
              status: { type: "string", description: "Filter: active, terminal", required: false }
            }
          },
          "update_agent_goal" => {
            description: "Update goal progress or status",
            parameters: {
              goal_id: { type: "string", description: "Goal ID to update", required: true },
              progress: { type: "number", description: "Progress 0.0 to 1.0", required: false },
              status: { type: "string", description: "New status", required: false }
            }
          },
          "agent_introspect" => {
            description: "View own execution history, trust score, performance, and budget",
            parameters: {
              agent_id: { type: "string", description: "Target agent ID (omit for self)", required: false }
            }
          },
          "propose_feature" => {
            description: "Create a feature suggestion for human review",
            parameters: {
              title: { type: "string", description: "Proposal title", required: true },
              description: { type: "string", description: "Detailed description", required: true },
              rationale: { type: "string", description: "Why this should be done", required: false },
              priority: { type: "string", description: "low, medium, high, critical", required: false },
              impact_assessment: { type: "object", description: "Scope, risk, effort", required: false }
            }
          },
          "send_proactive_notification" => {
            description: "Notify users about detected issues or suggestions",
            parameters: {
              user_id: { type: "string", description: "Target user ID (omit for account owner)", required: false },
              title: { type: "string", description: "Notification title", required: true },
              message: { type: "string", description: "Notification body", required: true },
              severity: { type: "string", description: "info, warning, error", required: false }
            }
          },
          "discover_claude_sessions" => {
            description: "Find active Claude Code MCP client sessions",
            parameters: {}
          },
          "request_code_change" => {
            description: "Request code changes via workspace message to a Claude session",
            parameters: {
              description: { type: "string", description: "What code change is needed", required: true },
              files_affected: { type: "array", description: "List of file paths", required: false },
              priority: { type: "string", description: "low, medium, high", required: false },
              evidence: { type: "object", description: "Supporting evidence", required: false }
            }
          },
          "create_proposal" => {
            description: "Formally propose a change for human review",
            parameters: {
              proposal_type: { type: "string", description: "feature, knowledge_update, code_change, architecture, process_improvement, configuration", required: true },
              title: { type: "string", description: "Proposal title", required: true },
              description: { type: "string", description: "Detailed description", required: true },
              rationale: { type: "string", description: "Why this should be done", required: false },
              priority: { type: "string", description: "low, medium, high, critical", required: false },
              proposed_changes: { type: "object", description: "Structured changes", required: false }
            }
          },
          "escalate" => {
            description: "Structured escalation when stuck or encountering issues",
            parameters: {
              title: { type: "string", description: "Escalation title", required: true },
              escalation_type: { type: "string", description: "stuck, error, budget_exceeded, approval_timeout, quality_concern, security_issue", required: true },
              severity: { type: "string", description: "low, medium, high, critical", required: false },
              context: { type: "object", description: "What was tried, error details, what is needed", required: false }
            }
          },
          "request_feedback" => {
            description: "Request user feedback on completed work",
            parameters: {
              user_id: { type: "string", description: "Target user ID (omit for recent interactor)", required: false },
              context_type: { type: "string", description: "Ai::AgentExecution, Ai::AgentProposal, etc.", required: false },
              context_id: { type: "string", description: "ID of the context item", required: false },
              message: { type: "string", description: "What feedback is being requested for", required: true }
            }
          },
          "report_issue" => {
            description: "Report a detected platform issue",
            parameters: {
              title: { type: "string", description: "Issue title", required: true },
              description: { type: "string", description: "Issue details", required: true },
              severity: { type: "string", description: "info, warning, critical", required: false },
              evidence: { type: "object", description: "Supporting data", required: false }
            }
          },
          "decompose_goal" => {
            description: "Decompose a goal into sub-goals using autonomous planning",
            parameters: {
              goal_id: { type: "string", description: "Goal ID to decompose", required: true },
              max_sub_goals: { type: "integer", description: "Maximum sub-goals to create (default 5)", required: false }
            }
          },
          # === Intervention policies (CRUD) ===
          "list_intervention_policies" => {
            description: "List intervention policies for the current account. Filterable by agent, action_category, is_active.",
            parameters: {
              agent_id: { type: "string", required: false, description: "Filter by agent" },
              action_category: { type: "string", required: false, description: "Filter by action category" },
              is_active: { type: "boolean", required: false, description: "Filter by active flag" }
            }
          },
          "create_intervention_policy" => {
            description: "Create a new intervention policy that gates autonomous actions for an agent (or all agents in scope).",
            parameters: {
              scope: { type: "string", required: true, description: "global | agent | team" },
              ai_agent_id: { type: "string", required: false, description: "Agent (when scope=agent)" },
              action_category: { type: "string", required: true, description: "Action category to gate (e.g. system.module_assign)" },
              policy: { type: "string", required: true, description: "auto_approve | notify_and_proceed | require_approval | silent | block" },
              conditions: { type: "object", required: false, description: "JSON match conditions" },
              priority: { type: "integer", required: false, description: "Higher priority wins on conflict (default 0)" },
              approval_chain_id: { type: "string", required: false, description: "Approval chain UUID (when policy=require_approval)" }
            }
          },
          "update_intervention_policy" => {
            description: "Update an existing intervention policy. Pass only the fields to change.",
            parameters: {
              policy_id: { type: "string", required: true, description: "Intervention policy UUID" },
              policy: { type: "string", required: false, description: "auto_approve | notify_and_proceed | require_approval | silent | block" },
              conditions: { type: "object", required: false, description: "Merged into existing conditions" },
              priority: { type: "integer", required: false, description: "Higher priority wins on conflict" },
              is_active: { type: "boolean", required: false, description: "Enable or disable this policy" }
            }
          },
          "delete_intervention_policy" => {
            description: "Permanently delete an intervention policy.",
            parameters: {
              policy_id: { type: "string", required: true, description: "Intervention policy UUID" }
            }
          },
          # === Deferred operations (approval queue) ===
          "list_deferred_operations" => {
            description: "List deferred operations (queued autonomous actions awaiting approval or completion).",
            parameters: {
              status: { type: "string", required: false, description: "pending | approved | rejected | completed | failed" },
              agent_id: { type: "string", required: false, description: "Filter by agent" },
              limit: { type: "integer", required: false, description: "Max results (default 25, max 100)" }
            }
          },
          "approve_deferred_operation" => {
            description: "Approve a pending deferred operation via the approval workflow. Triggers the underlying ApprovalRequest's approve path which will execute the action when the final step approves.",
            parameters: {
              deferred_operation_id: { type: "string", required: true, description: "DeferredOperation UUID OR ApprovalRequest UUID" },
              comments: { type: "string", required: false, description: "Optional approval comment" }
            }
          },
          "reject_deferred_operation" => {
            description: "Reject a pending deferred operation. Sets the request to rejected and the deferred op never executes.",
            parameters: {
              deferred_operation_id: { type: "string", required: true, description: "DeferredOperation UUID OR ApprovalRequest UUID" },
              comments: { type: "string", required: false, description: "Reason for rejection (recommended)" }
            }
          },
          # === Delegation authority (HIER-P0) ===
          "describe_delegation" => {
            description: "Describe an agent's delegation authority: its delegation policy (the account's own row, else the canonical global row, else none) and its resolved effective authority (trust tier + capability matrix). Defaults to the calling agent.",
            parameters: {
              agent_id: { type: "string", required: false, description: "Target agent ID (omit for self)" }
            }
          },
          "set_delegation_policy" => {
            description: "PROPOSE a delegation policy for an agent (self by default). Approval-gated under ai.delegation_policy.update — by default the call returns a pending approval envelope and no policy is written until an operator approves; an agent may propose its own authority, never grant it. Naming another agent is a lateral rewrite of THAT agent's authority and additionally requires ai.autonomy.manage, the permission its REST twin charges. Creates the account's row for the agent or updates the existing one.",
            parameters: {
              agent_id: { type: "string", required: false, description: "Target agent ID (omit for self; another agent's ID requires ai.autonomy.manage)" },
              max_depth: { type: "integer", required: false, description: "Maximum delegation depth, 1..10" },
              allowed_delegate_types: { type: "array", required: false, description: "Agent types this agent may delegate to (empty = any)" },
              delegatable_actions: { type: "array", required: false, description: "Action types this agent may delegate (empty = any)" },
              budget_delegation_pct: { type: "number", required: false, description: "Fraction 0..1 of remaining budget delegatable per task" },
              inheritance_policy: { type: "string", required: false, description: "conservative | moderate | permissive" }
            }
          }
        }
      end

      def call(params)
        # ONE normalized action drives both the gate and the dispatch, so the
        # permission that was checked always belongs to the branch that runs.
        # Deriving them from two expressions is how a gate and its dispatch come
        # to disagree.
        action = params[:action].to_s
        unless action_permitted?(action)
          # Logged, not just returned. This refusal is a soft error_result — the
          # surface's own idiom, and what the caller can act on — but a bare
          # result is invisible: on the agent path it becomes an ordinary tool
          # message fed back to the model, so a caller repeatedly attempting an
          # approval it cannot hold would leave no trace anywhere. The floor
          # denial one layer up raises and is logged by the registrar; this is
          # the matching record for the per-action denial.
          Rails.logger.warn(
            "[AgentAutonomyTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case action
        when "create_agent_goal" then create_agent_goal(params)
        when "list_agent_goals" then list_agent_goals(params)
        when "update_agent_goal" then update_agent_goal(params)
        when "agent_introspect" then agent_introspect(params)
        when "propose_feature" then propose_feature(params)
        when "send_proactive_notification" then send_proactive_notification(params)
        when "discover_claude_sessions" then discover_claude_sessions(params)
        when "request_code_change" then request_code_change(params)
        when "create_proposal" then create_proposal(params)
        when "escalate" then escalate(params)
        when "request_feedback" then request_feedback(params)
        when "report_issue" then report_issue(params)
        when "decompose_goal" then decompose_goal(params)
        when "list_intervention_policies" then list_intervention_policies(params)
        when "create_intervention_policy" then create_intervention_policy(params)
        when "update_intervention_policy" then update_intervention_policy(params)
        when "delete_intervention_policy" then delete_intervention_policy(params)
        when "list_deferred_operations" then list_deferred_operations(params)
        when "approve_deferred_operation" then approve_deferred_operation(params)
        when "reject_deferred_operation" then reject_deferred_operation(params)
        when "describe_delegation" then describe_delegation(params)
        when "set_delegation_policy" then set_delegation_policy(params)
        else
          error_result("Unknown action: #{action}")
        end
      end

      protected

      # A GATED action (set_delegation_policy) returns from BaseTool#execute
      # before #call, so the per-action permission check at the top of #call
      # would be skipped for exactly the action that needs it most. This is
      # the seam BaseTool provides for that: the same #action_permitted? the
      # ungated path runs, keyed on the routed action, never params[:action].
      def authorization_error(params)
        action = routed_action_name(params)
        required = effective_perm_for(action, params)
        return nil if action_permitted?(action, required)

        Rails.logger.warn(
          "[AgentAutonomyTool] Refused gated action for insufficient permission: " \
          "action=#{action} requires=#{required} user=#{user&.id}"
        )
        error_result("permission denied: #{required} required")
      end

      private

      # === Per-action permission gating (IMP-e8adfcfcab9b) ===

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # HIER-P0 — the operator ruling priced set_delegation_policy at
      # ai.agents.update because an agent PROPOSES ITS OWN authority
      # (guidance-agent-escalation). A proposal aimed at a THIRD agent is a
      # different act: under an operator's auto_approve row for
      # ai.delegation_policy.update it rewrites that agent's delegation
      # authority laterally, which is exactly what the REST twin charges
      # ai.autonomy.manage for (Ai::AutonomyWriteActions#require_write_permission).
      # Charged from #authorization_error, i.e. BEFORE Ai::AutonomyGate, so a
      # foreign proposal is not even parked as a pending approval.
      CROSS_AGENT_DELEGATION_PERMISSION = "ai.autonomy.manage"

      def effective_perm_for(action, params)
        return required_perm_for(action) unless action == "set_delegation_policy"
        return required_perm_for(action) unless cross_agent_delegation_target?(params)

        CROSS_AGENT_DELEGATION_PERMISSION
      end

      # Params arrive string-keyed from the registrar and symbol-keyed from the
      # DeferredToolCall replay, so the read goes through #indifferent — a
      # string-only read here would make every replayed foreign proposal look
      # like a self-proposal.
      def cross_agent_delegation_target?(params)
        target_id = indifferent(params)["agent_id"].presence
        return false if target_id.nil?

        agent.nil? || target_id.to_s != agent.id.to_s
      end

      # Two bypasses, both EXPLICIT, matching the sibling tools' ladder:
      #
      #   internal?            in-process system callers (autonomy reconcilers,
      #                        skill executors running without a user) that
      #                        opted in with `internal: true`. Never inferred
      #                        from a nil user — an MCP instance principal also
      #                        arrives with none (IMP-9030413bc292).
      #   instance_authorized? an mTLS node principal whose SPECIFIC tool name
      #                        already cleared Mcp::Principal#may_invoke? in the
      #                        streamable controller, and whose action the
      #                        registrar then pins to that same name. Without
      #                        this arm every such call is hard-denied (BUG-R).
      #
      # Unlike those siblings there is no `return true unless
      # user.respond_to?(:has_permission?)` arm. That arm fails OPEN, and it is
      # unreachable here anyway: REQUIRED_PERMISSION is no longer nil, so the
      # registrar has already called user.has_permission? on any caller that
      # gets this far. A principal that cannot answer the question is refused.
      def action_permitted?(action, required = required_perm_for(action))
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer, and a truthy non-boolean must
        # not read as a grant.
        user.has_permission?(required) == true
      end

      def create_agent_goal(params)
        target_agent = resolve_agent(params["agent_id"])
        return error_result("Agent not found") unless target_agent

        goal = Ai::AgentGoal.create(
          account: account,
          ai_agent_id: target_agent.id,
          created_by: agent,
          title: params["title"],
          description: params["description"],
          goal_type: params["goal_type"],
          priority: params["priority"] || 3,
          parent_goal_id: params["parent_goal_id"],
          success_criteria: params["success_criteria"] || {}
        )

        if goal.persisted?
          success_result(id: goal.id, title: goal.title, status: goal.status)
        else
          error_result(goal.errors.full_messages.join(", "))
        end
      end

      def list_agent_goals(params)
        target_agent = resolve_agent(params["agent_id"])
        return error_result("Agent not found") unless target_agent

        goals = Ai::AgentGoal.for_agent(target_agent.id)
        goals = params["status"] == "terminal" ? goals.terminal : goals.active
        goals = goals.by_priority.limit(10)

        success_result(goals: goals.map { |g|
          { id: g.id, title: g.title, type: g.goal_type, priority: g.priority,
            status: g.status, progress: g.progress.to_f }
        })
      end

      def update_agent_goal(params)
        goal = account.ai_agent_goals.find_by(id: params["goal_id"])
        return error_result("Goal not found") unless goal

        if params["progress"].present?
          goal.update_progress!(params["progress"].to_f)
        elsif params["status"].present?
          case params["status"]
          when "achieved" then goal.achieve!
          when "abandoned" then goal.abandon!
          when "failed" then goal.fail!
          when "active" then goal.activate!
          when "paused" then goal.pause!
          end
        end

        success_result(id: goal.id, status: goal.status, progress: goal.progress.to_f)
      end

      def agent_introspect(params)
        target_agent = resolve_agent(params["agent_id"])
        return error_result("Agent not found") unless target_agent

        trust_score = Ai::AgentTrustScore.find_by(agent_id: target_agent.id)
        budget = Ai::AgentBudget.where(agent_id: target_agent.id).active.first

        recent = Ai::AgentExecution.where(ai_agent_id: target_agent.id).where("created_at >= ?", 24.hours.ago)
        total_24h = recent.count
        failed_24h = recent.where(status: "failed").count

        success_result(
          agent: { id: target_agent.id, name: target_agent.name, status: target_agent.status },
          trust: trust_score ? {
            tier: trust_score.tier,
            overall_score: trust_score.overall_score&.round(3),
            last_evaluated: trust_score.last_evaluated_at&.iso8601
          } : nil,
          budget: budget ? {
            remaining_cents: budget.remaining_cents,
            allocated_cents: budget.allocated_cents,
            utilization_pct: budget.utilization_percentage
          } : nil,
          performance_24h: {
            total_executions: total_24h,
            failed: failed_24h,
            failure_rate: total_24h > 0 ? (failed_24h.to_f / total_24h * 100).round(1) : 0
          },
          active_goals: Ai::AgentGoal.for_agent(target_agent.id).active.count,
          pending_observations: Ai::AgentObservation.where(ai_agent_id: target_agent.id, processed: false).count
        )
      end

      def propose_feature(params)
        service = Ai::ProposalService.new(account: account)
        proposal = service.create(
          agent: agent,
          params: {
            proposal_type: "feature",
            title: params["title"],
            description: params["description"],
            rationale: params["rationale"],
            priority: params["priority"] || "medium",
            impact_assessment: params["impact_assessment"] || {}
          }
        )

        if proposal.persisted?
          success_result(id: proposal.id, title: proposal.title, status: proposal.status)
        else
          error_result(proposal.errors.full_messages.join(", "))
        end
      end

      def send_proactive_notification(params)
        user = if params["user_id"].present?
          account.users.find_by(id: params["user_id"])
        else
          account.owner
        end
        return error_result("User not found") unless user

        outreach = Ai::AgentOutreachService.new(account: account, agent: agent)
        result = outreach.notify(
          user: user,
          type: "agent_status_update",
          title: params["title"],
          message: params["message"],
          severity: params["severity"] || "info"
        )

        success_result(result)
      end

      def discover_claude_sessions(_params)
        service = Ai::Autonomy::ClaudeSessionDiscoveryService.new(account: account)
        sessions = service.active_sessions

        success_result(sessions: sessions, count: sessions.size)
      end

      def request_code_change(params)
        service = Ai::Autonomy::ClaudeSessionDiscoveryService.new(account: account)
        session = service.most_recent_session

        unless session
          return error_result("No active Claude Code session found")
        end

        # Create a workspace message with structured code change request
        conversation = Ai::Conversation
          .where(account_id: account.id)
          .where(conversation_type: "workspace")
          # a conversation's agent is the ai_agent_id column (no participants join table)
          .where(ai_agent_id: session[:agent_id])
          .order(updated_at: :desc)
          .first

        unless conversation
          return error_result("No workspace conversation found for Claude session")
        end

        message = conversation.messages.create!(
          account_id: account.id,
          role: "assistant",
          content: "**Code Change Request**\n\n#{params['description']}",
          ai_agent_id: agent.id,
          content_metadata: {
            activity_type: "code_change_request",
            request_id: SecureRandom.uuid,
            requesting_agent_id: agent.id,
            description: params["description"],
            files_affected: params["files_affected"] || [],
            priority: params["priority"] || "medium",
            evidence: params["evidence"] || {}
          }
        )

        success_result(message_id: message.id, session: session[:agent_name])
      end

      def create_proposal(params)
        service = Ai::ProposalService.new(account: account)
        proposal = service.create(
          agent: agent,
          params: params.slice("proposal_type", "title", "description", "rationale", "priority", "proposed_changes")
            .transform_keys(&:to_sym)
        )

        if proposal.persisted?
          success_result(id: proposal.id, title: proposal.title, status: proposal.status)
        else
          error_result(proposal.errors.full_messages.join(", "))
        end
      end

      def escalate(params)
        service = Ai::EscalationService.new(account: account)
        escalation = service.escalate(
          agent: agent,
          title: params["title"],
          escalation_type: params["escalation_type"],
          severity: params["severity"] || "medium",
          context: params["context"] || {}
        )

        forwarded = forward_to_external_tracker(
          kind: "escalation",
          title: params["title"],
          body: stringify_body(params["context"]).presence || params["escalation_type"].to_s,
          severity: escalation.severity,
          metadata: { escalation_type: params["escalation_type"], agent_id: agent&.id, escalation_id: escalation.id }
        )

        data = { id: escalation.id, title: escalation.title, severity: escalation.severity,
                 escalated_to: escalation.escalated_to_user&.email }
        data[:external_tracker] = forwarded if forwarded
        success_result(data)
      end

      def request_feedback(params)
        user = if params["user_id"].present?
          account.users.find_by(id: params["user_id"])
        else
          account.owner
        end
        return error_result("User not found") unless user

        outreach = Ai::AgentOutreachService.new(account: account, agent: agent)
        result = outreach.notify(
          user: user,
          type: "agent_feedback_request",
          title: "Feedback requested",
          message: params["message"],
          severity: "info",
          action_url: params["context_id"].present? ? "/ai/feedback?context_id=#{params['context_id']}" : "/ai/feedback"
        )

        success_result(result)
      end

      def report_issue(params)
        # Create an observation for the issue
        observation = Ai::AgentObservation.create(
          account: account,
          ai_agent_id: agent.id,
          sensor_type: "platform_health",
          observation_type: "alert",
          severity: params["severity"] || "warning",
          title: params["title"],
          data: {
            description: params["description"],
            evidence: params["evidence"] || {},
            reported_by_agent: agent.id
          },
          requires_action: true,
          expires_at: 24.hours.from_now
        )

        # Also notify account admins
        outreach = Ai::AgentOutreachService.new(account: account, agent: agent)
        admin = account.owner
        if admin
          # Renders a critical issue as the notification severity "error" (see
          # Ai::AgentOutreachService#notify_escalation for why), so it has to
          # DECLARE criticality to the policy layer rather than let it be
          # inferred from that word — otherwise a critical issue report is
          # withheld once the daily notification budget is spent
          # (IMP-34beef811fdf).
          issue_critical = params["severity"] == "critical"

          outreach.notify(
            user: admin,
            type: "agent_issue_detected",
            title: "Issue detected: #{params['title']}",
            message: params["description"],
            severity: issue_critical ? "error" : "warning",
            policy_severity: issue_critical ? "critical" : nil
          )
        end

        forwarded = forward_to_external_tracker(
          kind: "issue",
          title: params["title"],
          body: params["description"],
          severity: params["severity"] || "warning",
          metadata: { evidence: params["evidence"] || {}, agent_id: agent&.id, observation_id: observation.id }
        )

        data = { observation_id: observation.id, title: params["title"] }
        data[:external_tracker] = forwarded if forwarded
        success_result(data)
      end

      # Best-effort, opt-in bridge to an OUTBOUND issue/error tracker. No-op unless
      # a tracker is configured (Ai::Connectors::TrackerConfig); failures never
      # break the internal report_issue / escalate path.
      def forward_to_external_tracker(**kwargs)
        Ai::Connectors::TrackerBridge.forward(**kwargs)
      rescue StandardError => e
        Rails.logger.warn("[AgentAutonomyTool] external tracker forward failed: #{e.class}: #{e.message}")
        nil
      end

      def stringify_body(value)
        return "" if value.blank?

        value.is_a?(String) ? value : value.to_json
      end

      def decompose_goal(params)
        goal = account.ai_agent_goals.find_by(id: params["goal_id"])
        return error_result("Goal not found") unless goal

        max_sub = (params["max_sub_goals"] || 5).to_i
        service = Ai::Autonomy::GoalDecompositionService.new(account: account, agent: agent)
        result = service.decompose(goal: goal, max_sub_goals: max_sub)
        success_result(result)
      rescue NameError
        error_result("Goal decomposition service not available")
      rescue StandardError => e
        error_result("Failed to decompose goal: #{e.message}")
      end

      def resolve_agent(agent_id)
        if agent_id.present?
          ::Ai::Agent.for_account(account.id).find_by(id: agent_id)
        else
          agent
        end
      end

      # === Delegation authority (HIER-P0) ===

      def describe_delegation(params)
        p = indifferent(params)
        target_agent = resolve_agent(p["agent_id"])
        return error_result("Agent not found") unless target_agent

        policy = Ai::DelegationPolicy.resolve_for(agent_id: target_agent.id, account_id: account.id)
        authority = Ai::Autonomy::DelegationAuthorityService.new(account: account)
          .effective_capabilities(agent: target_agent)

        success_result(
          agent: { id: target_agent.id, name: target_agent.name,
                   agent_type: target_agent.agent_type, status: target_agent.status,
                   canonical: target_agent.global? && target_agent.is_system == true },
          policy: policy ? serialize_delegation_policy(policy) : nil,
          effective_authority: authority
        )
      end

      # Runs ONLY on the gate's proceed branch — the DeferredToolCall replay
      # after an operator approved, or synchronously under an explicit
      # auto_approve intervention policy. The gate never reaches here on the
      # default require_approval path; BaseTool#execute returns the pending
      # envelope instead. Always writes the ACCOUNT's row: a canonical global
      # row is seed-managed and never edited from an agent surface.
      def set_delegation_policy(params)
        p = indifferent(params)
        target_agent = resolve_agent(p["agent_id"])
        return error_result("Agent not found") unless target_agent

        policy = Ai::DelegationPolicy.find_or_initialize_by(account_id: account.id, agent_id: target_agent.id)
        attrs = DELEGATION_POLICY_FIELDS.each_with_object({}) do |field, acc|
          acc[field] = p[field] if p.key?(field)
        end
        policy.assign_attributes(attrs)
        policy.save!

        success_result(agent_id: target_agent.id, policy: serialize_delegation_policy(policy))
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      DELEGATION_POLICY_FIELDS = %w[
        max_depth allowed_delegate_types delegatable_actions budget_delegation_pct inheritance_policy
      ].freeze
      private_constant :DELEGATION_POLICY_FIELDS

      def serialize_delegation_policy(policy)
        {
          id: policy.id,
          agent_id: policy.agent_id,
          canonical: policy.global?,
          max_depth: policy.max_depth,
          allowed_delegate_types: policy.allowed_delegate_types,
          delegatable_actions: policy.delegatable_actions,
          budget_delegation_pct: policy.budget_delegation_pct,
          inheritance_policy: policy.inheritance_policy
        }
      end

      # Params arrive indifferent from McpPlatformToolRegistrar but SYMBOL-keyed
      # from the DeferredToolCall replay (it deep_symbolize_keys the parked
      # copy); string reads against the latter would silently see nothing.
      def indifferent(params)
        raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        raw.with_indifferent_access
      end

      # === Intervention policies ===

      def list_intervention_policies(params)
        scope = account.ai_intervention_policies
        scope = scope.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?
        scope = scope.where(action_category: params[:action_category]) if params[:action_category].present?
        scope = scope.where(is_active: params[:is_active]) unless params[:is_active].nil?

        policies = scope.order(priority: :desc, created_at: :desc).limit(100)
        {
          success: true, count: policies.size,
          policies: policies.map { |p|
            { id: p.id, scope: p.scope, ai_agent_id: p.ai_agent_id, action_category: p.action_category,
              policy: p.policy, priority: p.priority, is_active: p.is_active,
              approval_chain_id: p.approval_chain_id, conditions: p.conditions }
          }
        }
      end

      def create_intervention_policy(params)
        policy = account.ai_intervention_policies.create!(
          scope: params[:scope],
          ai_agent_id: params[:ai_agent_id],
          action_category: params[:action_category],
          policy: params[:policy],
          conditions: params[:conditions] || {},
          priority: params[:priority] || 0,
          approval_chain_id: params[:approval_chain_id],
          is_active: true,
          user_id: user&.id
        )
        { success: true, policy_id: policy.id, policy: policy.policy }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def update_intervention_policy(params)
        policy = account.ai_intervention_policies.find_by(id: params[:policy_id])
        return { success: false, error: "Intervention policy not found" } unless policy

        attrs = {}
        attrs[:policy] = params[:policy] if params[:policy].present?
        attrs[:priority] = params[:priority] if params.key?(:priority)
        attrs[:is_active] = params[:is_active] unless params[:is_active].nil?
        attrs[:conditions] = (policy.conditions || {}).merge(params[:conditions]) if params[:conditions].present?

        policy.update!(attrs)
        { success: true, policy_id: policy.id, policy: policy.policy, is_active: policy.is_active }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def delete_intervention_policy(params)
        policy = account.ai_intervention_policies.find_by(id: params[:policy_id])
        return { success: false, error: "Intervention policy not found" } unless policy
        policy.destroy!
        { success: true, deleted: true, policy_id: params[:policy_id] }
      end

      # === Deferred operations (approval queue) ===

      def list_deferred_operations(params)
        scope = account.ai_deferred_operations
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?
        limit = (params[:limit] || 25).to_i.clamp(1, 100)
        ops = scope.order(created_at: :desc).limit(limit)
        {
          success: true, count: ops.size,
          operations: ops.map { |o|
            { id: o.id, status: o.status, ai_agent_id: o.ai_agent_id, action_category: o.action_category,
              executor_class: o.executor_class, description: o.description,
              approval_request_id: o.approval_request_id, source_type: o.source_type,
              created_at: o.created_at.iso8601, executed_at: o.executed_at&.iso8601 }
          }
        }
      end

      def approve_deferred_operation(params)
        request = resolve_approval_request(params[:deferred_operation_id])
        return { success: false, error: "ApprovalRequest not found" } unless request

        result = ::Ai::Autonomy::ApprovalWorkflowService.new(account: account).approve(
          request: request, approver: user, comments: params[:comments]
        )
        # Deliberately does NOT carry the reveal-once handoff (IMP-7b81ca22f661)
        # that the HTTP approval surfaces do. A tool return travels further than
        # its caller: Ai::AgentToolBridgeService puts a 200-byte preview of it in
        # `tool_calls_log` — persisted to ai_messages.processing_metadata — and
        # appends the full JSON as a role:"tool" message sent to the model
        # provider on the next turn. Revealing minted key material here would
        # make it a durable plaintext copy AND transmit it off-platform, which
        # is the invariant that handoff exists to preserve, not an edge case of
        # it. Approving through this surface therefore still destroys a mint;
        # the token is disclosed on the operator UI/API surface instead.
        { success: true, approval_request_id: request.id, request_status: request.reload.status, workflow: result }
      rescue StandardError => e
        { success: false, error: "Approval failed: #{e.class}: #{e.message}" }
      end

      def reject_deferred_operation(params)
        request = resolve_approval_request(params[:deferred_operation_id])
        return { success: false, error: "ApprovalRequest not found" } unless request

        result = ::Ai::Autonomy::ApprovalWorkflowService.new(account: account).reject(
          request: request, approver: user, comments: params[:comments]
        )
        { success: true, approval_request_id: request.id, request_status: request.reload.status, workflow: result }
      rescue StandardError => e
        { success: false, error: "Rejection failed: #{e.class}: #{e.message}" }
      end

      # Accepts either a DeferredOperation id (looks up its approval_request) or an ApprovalRequest id directly.
      def resolve_approval_request(id)
        return nil if id.blank?
        deferred = account.ai_deferred_operations.find_by(id: id)
        if deferred
          deferred.approval_request_id ? ::Ai::ApprovalRequest.find_by(id: deferred.approval_request_id) : nil
        else
          ::Ai::ApprovalRequest.where(account_id: account.id).find_by(id: id)
        end
      end
    end
  end
end
