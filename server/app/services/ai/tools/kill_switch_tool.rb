# frozen_string_literal: true

module Ai
  module Tools
    class KillSwitchTool < BaseTool
      tool_family "governance"

      REQUIRED_PERMISSION = "ai.kill_switch.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      # emergency_halt is DELIBERATELY ungated (Ai::ClaudeExport::ThinLoader::UNGATED_BY_DECISION):
      # the kill switch must act at once for a human session, so it never parks. Agents
      # stay denied it by name (ThinLoader::DENIED_DESTRUCTIVE_ACTIONS); resuming is the
      # slow, human-only direction.
      declare_action "emergency_halt", mutating: true, destructive: true
      declare_action "emergency_resume", mutating: true, destructive: true,
                                         human_only: true,
                                         action_category: "ai.kill_switch.resume",
                                         executor_class: "Ai::Executors::DeferredToolCall",
                                         gate_context: :deferred_tool_call_context,
                                         on_proceed: :deferred_tool_call_result
      declare_action "kill_switch_status", mutating: false,
                                           returns: "halted, since, a snapshot preview while halted, and the latest halt event"

      def self.definition
        {
          name: "kill_switch",
          description: "Emergency AI kill switch: halt all AI activity, resume operations, or check suspension status",
          parameters: {
            action: { type: "string", required: true, description: "Action: emergency_halt, emergency_resume, kill_switch_status" },
            reason: { type: "string", required: false, description: "Reason for halt (for emergency_halt)" },
            mode: { type: "string", required: false, description: "Resume mode: 'full' (restore snapshot) or 'minimal' (lift suspension only). Default: full" }
          }
        }
      end

      def self.action_definitions
        {
          "emergency_halt" => {
            description: "Emergency halt ALL AI activity for the account. Cancels running executions, pauses schedules, blocks LLM calls, and demotes all agents to supervised tier.",
            parameters: {
              reason: { type: "string", required: false, description: "Reason for the emergency halt" }
            }
          },
          "emergency_resume" => {
            description: "Resume AI activity after an emergency halt. 'full' mode restores agent trust tiers and schedules from pre-halt snapshot. 'minimal' mode only lifts the suspension.",
            parameters: {
              mode: { type: "string", required: false, description: "Resume mode: 'full' (restore snapshot, default) or 'minimal' (lift suspension only)" }
            }
          },
          "kill_switch_status" => {
            description: "Check if AI activity is currently suspended. Returns halted status, timestamp, and snapshot preview.",
            parameters: {}
          }
        }
      end

      # Override: kill_switch_status should be readable by any agent.
      #
      # HIER-P2I: "any agent" still excludes a GLOBAL canonical. This override
      # does not call super, so BaseTool's fail-closed line never runs for it —
      # without the check here `PlatformApiToolRegistry.advertised_class?` would
      # keep advertising the kill switch to a canonical and
      # `Ai::Executors::DeferredToolCall#authorized?` would answer authorized
      # for a row it parked, both of which the ruling says must fail closed.
      def self.permitted?(agent:)
        return false if canonical_principal?(agent)

        true
      end

      protected

      # emergency_resume is human_only and so returns from BaseTool#execute before
      # #call. The person who confirms it must hold the tool's own permission, so a
      # holder of ai.autonomy.approve alone cannot lift the suspension: checked
      # before the park and again at replay (c13-2 batch C-C). A caller with no
      # user (an agent) is refused, since resuming runs as a person.
      def authorization_error(_params)
        return nil if internal?
        return nil if user.respond_to?(:has_permission?) && user.has_permission?(REQUIRED_PERMISSION) == true

        error_result("permission denied: #{REQUIRED_PERMISSION} required")
      end

      def call(params)
        case params[:action]
        when "emergency_halt" then emergency_halt(params)
        when "emergency_resume" then emergency_resume(params)
        when "kill_switch_status" then kill_switch_status
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid: emergency_halt, emergency_resume, kill_switch_status" }
        end
      end

      private

      def service
        @service ||= ::Ai::Autonomy::KillSwitchService.new(account: account)
      end

      def emergency_halt(params)
        # Require a user context for audit trail (agent can trigger if autonomous)
        triggering_user = user || find_account_owner
        unless triggering_user
          return { success: false, error: "Cannot identify triggering user for audit trail" }
        end

        reason = params[:reason] || "Emergency halt triggered via MCP tool"
        event = service.emergency_halt!(reason: reason, triggered_by: triggering_user)

        {
          success: true,
          event_id: event.id,
          message: "AI activity halted for account",
          impact: event.impact
        }
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to activate kill switch")
      end

      def emergency_resume(params)
        triggering_user = user || find_account_owner
        unless triggering_user
          return { success: false, error: "Cannot identify triggering user for audit trail" }
        end

        mode = %w[full minimal].include?(params[:mode]) ? params[:mode].to_sym : :full
        event = service.resume!(triggered_by: triggering_user, mode: mode)

        if event
          {
            success: true,
            event_id: event.id,
            message: "AI activity resumed (mode: #{mode})",
            restored_from_snapshot: event.metadata&.dig("restored_from_snapshot") || false
          }
        else
          { success: false, error: "AI activity is not currently suspended" }
        end
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to resume")
      end

      def kill_switch_status
        status = service.status
        { success: true, **status }
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to check status")
      end

      def find_account_owner
        account.owner
      end
    end
  end
end
