# frozen_string_literal: true

module Ai
  module Tools
    class AgentAutonomyTool < BaseTool
      def self.definition
        {
          name: "agent_autonomy",
          description: "Agent autonomy tools: goals, proposals, escalations, introspection, proactive notifications, and code change requests",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_agent_goal, list_agent_goals, update_agent_goal, agent_introspect, propose_feature, send_proactive_notification, discover_claude_sessions, request_code_change, create_proposal, escalate, request_feedback, report_issue" }
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
          }
        }
      end

      def call(params)
        case params[:action]
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
        else
          error_result("Unknown action: #{params[:action]}")
        end
      end

      private

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
          .joins(:participants)
          .where(ai_conversation_participants: { ai_agent_id: session[:agent_id] })
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

        success_result(id: escalation.id, title: escalation.title, severity: escalation.severity,
                       escalated_to: escalation.escalated_to_user&.email)
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
          outreach.notify(
            user: admin,
            type: "agent_issue_detected",
            title: "Issue detected: #{params['title']}",
            message: params["description"],
            severity: params["severity"] == "critical" ? "error" : "warning"
          )
        end

        success_result(observation_id: observation.id, title: params["title"])
      end

      def resolve_agent(agent_id)
        if agent_id.present?
          account.ai_agents.find_by(id: agent_id)
        else
          agent
        end
      end
    end
  end
end
