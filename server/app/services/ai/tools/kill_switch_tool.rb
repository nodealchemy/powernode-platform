# frozen_string_literal: true

module Ai
  module Tools
    class KillSwitchTool < BaseTool
      REQUIRED_PERMISSION = "ai.kill_switch.manage"

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

      # Override: kill_switch_status should be readable by any agent
      def self.permitted?(agent:)
        true
      end

      protected

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
        { success: false, error: "Failed to activate kill switch: #{e.message}" }
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
        { success: false, error: "Failed to resume: #{e.message}" }
      end

      def kill_switch_status
        status = service.status
        { success: true, **status }
      rescue StandardError => e
        { success: false, error: "Failed to check status: #{e.message}" }
      end

      def find_account_owner
        account.owner
      end
    end
  end
end
