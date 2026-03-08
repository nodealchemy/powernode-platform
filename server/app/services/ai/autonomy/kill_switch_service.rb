# frozen_string_literal: true

module Ai
  module Autonomy
    class KillSwitchService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Coordinated emergency stop — halts ALL agentic activity for an account.
      # Captures a state snapshot before halting for later restore.
      #
      # @param reason [String] why the kill switch was activated
      # @param triggered_by [User] who triggered the halt
      # @return [Ai::KillSwitchEvent] the halt event record
      def emergency_halt!(reason:, triggered_by:)
        return latest_halt_event if halted?

        snapshot = capture_state_snapshot

        # Layer 1: Block new work
        account.suspend_ai!

        # Layer 2: Cancel in-flight executions
        cancelled_count = cancel_all_running_executions(reason)

        # Layer 3: Pause all schedules
        paused_loops = pause_all_ralph_loops
        paused_schedules = pause_all_workflow_schedules

        # Layer 4: Cancel queued A2A tasks
        cancelled_tasks = cancel_all_pending_a2a_tasks(reason)

        # Layer 5: Open all provider circuit breakers
        open_all_circuit_breakers

        # Layer 6: Demote all agents to supervised
        demoted_agents = demote_all_agents_to_supervised

        # Layer 7: Drain AI Sidekiq queues for this account
        drain_ai_queues

        # Record event with snapshot for restore
        event = create_event(
          event_type: "halt",
          reason: reason,
          triggered_by: triggered_by,
          metadata: {
            snapshot: snapshot,
            impact: {
              cancelled_executions: cancelled_count,
              paused_loops: paused_loops,
              paused_schedules: paused_schedules,
              cancelled_tasks: cancelled_tasks,
              demoted_agents: demoted_agents
            }
          }
        )

        broadcast_emergency_halt(reason)
        notify_account_users(reason)

        event
      end

      # Resume AI activity. Two modes:
      # - :full — restores agent trust tiers, Ralph loops, and workflow schedules from snapshot
      # - :minimal — only lifts the suspension flag and circuit breakers
      #
      # @param triggered_by [User]
      # @param mode [Symbol] :full or :minimal
      # @return [Ai::KillSwitchEvent] the resume event record
      def resume!(triggered_by:, mode: :full)
        return nil unless halted?

        snapshot = latest_halt_event&.snapshot

        # Lift suspension
        account.resume_ai!

        # Close circuit breakers
        close_all_circuit_breakers

        if mode.to_sym == :full && snapshot.present?
          restore_from_snapshot(snapshot)
        end

        event = create_event(
          event_type: "resume",
          reason: "AI activity resumed (mode: #{mode})",
          triggered_by: triggered_by,
          metadata: {
            resume_mode: mode.to_s,
            restored_from_snapshot: mode.to_sym == :full && snapshot.present?
          }
        )

        broadcast_resume
        event
      end

      # Preview what a full restore would do before committing.
      #
      # @return [Hash, nil] preview of restore actions or nil if not halted
      def preview_restore
        snapshot = latest_halt_event&.snapshot
        return nil unless snapshot

        agent_tiers = snapshot["agent_trust_tiers"] || {}
        {
          agents_to_restore: agent_tiers.count { |_, tier| tier != "supervised" },
          total_agents: agent_tiers.size,
          ralph_loops_to_resume: (snapshot["active_ralph_loops"] || []).size,
          workflow_schedules_to_resume: (snapshot["active_workflow_schedules"] || []).size,
          snapshot_taken_at: snapshot["captured_at"]
        }
      end

      # Check if AI activity is currently suspended.
      def halted?
        account.ai_suspended?
      end

      # Get the current status with context.
      def status
        {
          halted: halted?,
          since: halted? ? account.ai_suspended_at&.iso8601 : nil,
          snapshot_preview: halted? ? preview_restore : nil,
          latest_event: serialize_latest_event
        }
      end

      # Get the most recent halt event (for snapshot access).
      def latest_halt_event
        account.ai_kill_switch_events.halts.recent.first
      end

      # Event history for audit trail.
      def events(limit: 20)
        account.ai_kill_switch_events.recent.limit(limit)
      end

      private

      def serialize_latest_event
        event = latest_halt_event
        return nil unless event

        user = event.triggered_by
        {
          id: event.id,
          event_type: event.event_type,
          reason: event.reason,
          created_at: event.created_at.iso8601,
          triggered_by: user ? { id: user.id, email: user.email, name: user.name } : nil
        }
      end

      # ── Snapshot ─────────────────────────────────────────────

      def capture_state_snapshot
        {
          "captured_at" => Time.current.iso8601,
          "agent_trust_tiers" => account_agent_trust_tiers,
          "active_ralph_loops" => account_active_ralph_loop_ids,
          "active_workflow_schedules" => account_active_workflow_schedule_ids
        }
      end

      def account_agent_trust_tiers
        Ai::AgentTrustScore
          .joins(:agent)
          .where(ai_agents: { account_id: account.id })
          .pluck(:agent_id, :tier)
          .to_h
          .transform_keys(&:to_s)
      end

      def account_active_ralph_loop_ids
        account.ai_ralph_loops
          .where(schedule_paused: false)
          .where(status: %w[pending running paused])
          .pluck(:id)
          .map(&:to_s)
      end

      def account_active_workflow_schedule_ids
        Ai::WorkflowSchedule
          .joins(:workflow)
          .where(ai_workflows: { account_id: account.id })
          .where(is_active: true, status: "active")
          .pluck(:id)
          .map(&:to_s)
      end

      # ── Layer 1: Account suspension (handled by caller via account.suspend_ai!) ──

      # ── Layer 2: Cancel running executions ───────────────────

      def cancel_all_running_executions(reason)
        executions = Ai::AgentExecution
          .where(account_id: account.id)
          .where(status: %w[pending running])

        count = executions.count
        executions.find_each do |execution|
          execution.cancel_execution!("Kill switch activated: #{reason}")
        rescue StandardError => e
          Rails.logger.error "[KillSwitch] Failed to cancel execution #{execution.id}: #{e.message}"
        end
        count
      end

      # ── Layer 3: Pause schedules ─────────────────────────────

      def pause_all_ralph_loops
        loops = account.ai_ralph_loops.where(schedule_paused: false)
        count = loops.count
        loops.update_all(schedule_paused: true)
        count
      end

      def pause_all_workflow_schedules
        schedules = Ai::WorkflowSchedule
          .joins(:workflow)
          .where(ai_workflows: { account_id: account.id })
          .where(is_active: true)

        count = schedules.count
        schedules.update_all(is_active: false, status: "paused")
        count
      end

      # ── Layer 4: Cancel A2A tasks ────────────────────────────

      def cancel_all_pending_a2a_tasks(reason)
        tasks = Ai::A2aTask
          .where(account_id: account.id)
          .where(status: %w[pending active input_required])

        count = tasks.count
        tasks.find_each do |task|
          task.cancel!(reason: "Kill switch activated: #{reason}")
        rescue StandardError => e
          Rails.logger.error "[KillSwitch] Failed to cancel A2A task #{task.id}: #{e.message}"
        end
        count
      end

      # ── Layer 5: Circuit breakers ────────────────────────────

      def open_all_circuit_breakers
        breakers = Ai::CircuitBreaker
          .joins(:agent)
          .where(ai_agents: { account_id: account.id })
          .where.not(state: "open")

        breakers.find_each do |breaker|
          breaker.trip!(reason: "kill_switch_activated")
        rescue StandardError => e
          Rails.logger.error "[KillSwitch] Failed to open circuit breaker #{breaker.id}: #{e.message}"
        end
      end

      def close_all_circuit_breakers
        breakers = Ai::CircuitBreaker
          .joins(:agent)
          .where(ai_agents: { account_id: account.id })
          .where.not(state: "closed")

        breakers.find_each do |breaker|
          breaker.close!(reason: "kill_switch_resumed")
        rescue StandardError => e
          Rails.logger.error "[KillSwitch] Failed to close circuit breaker #{breaker.id}: #{e.message}"
        end
      end

      # ── Layer 6: Demote all agents ───────────────────────────

      def demote_all_agents_to_supervised
        trust_scores = Ai::AgentTrustScore
          .joins(:agent)
          .where(ai_agents: { account_id: account.id })
          .where.not(tier: "supervised")

        count = trust_scores.count
        trust_scores.update_all(tier: "supervised")
        count
      end

      # ── Layer 7: Drain Sidekiq queues ────────────────────────

      def drain_ai_queues
        # The account.ai_suspended flag is the source of truth.
        # Worker jobs check suspension via the internal API before executing.
        # No cross-Redis communication needed — workers call the server.
        Rails.logger.info "[KillSwitch] AI suspension flag set for account #{account.id}, workers will check via API"
      end

      # ── Restore from snapshot ────────────────────────────────

      def restore_from_snapshot(snapshot)
        restore_agent_trust_tiers(snapshot["agent_trust_tiers"])
        restore_ralph_loops(snapshot["active_ralph_loops"])
        restore_workflow_schedules(snapshot["active_workflow_schedules"])
      end

      def restore_agent_trust_tiers(tiers)
        return unless tiers.is_a?(Hash)

        tiers.each do |agent_id, tier|
          trust_score = Ai::AgentTrustScore.find_by(agent_id: agent_id)
          trust_score&.update!(tier: tier)
        rescue StandardError => e
          Rails.logger.error "[KillSwitch] Failed to restore trust tier for agent #{agent_id}: #{e.message}"
        end
      end

      def restore_ralph_loops(loop_ids)
        return unless loop_ids.is_a?(Array) && loop_ids.any?

        Ai::RalphLoop.where(id: loop_ids).update_all(schedule_paused: false)
      end

      def restore_workflow_schedules(schedule_ids)
        return unless schedule_ids.is_a?(Array) && schedule_ids.any?

        Ai::WorkflowSchedule.where(id: schedule_ids).update_all(is_active: true, status: "active")
      end

      # ── Event recording ──────────────────────────────────────

      def create_event(event_type:, reason:, triggered_by:, metadata: {})
        Ai::KillSwitchEvent.create!(
          account: account,
          triggered_by: triggered_by,
          event_type: event_type,
          reason: reason,
          metadata: metadata
        )
      end

      # ── Broadcasting & Notifications ─────────────────────────

      def broadcast_emergency_halt(reason)
        ActionCable.server.broadcast(
          "ai_orchestration_#{account.id}",
          {
            type: "kill_switch_activated",
            reason: reason,
            timestamp: Time.current.iso8601
          }
        )
      rescue StandardError => e
        Rails.logger.error "[KillSwitch] Failed to broadcast halt: #{e.message}"
      end

      def broadcast_resume
        ActionCable.server.broadcast(
          "ai_orchestration_#{account.id}",
          {
            type: "kill_switch_deactivated",
            timestamp: Time.current.iso8601
          }
        )
      rescue StandardError => e
        Rails.logger.error "[KillSwitch] Failed to broadcast resume: #{e.message}"
      end

      def notify_account_users(reason)
        Notification.create_for_account(
          account,
          type: "security_alert",
          title: "AI Emergency Stop Activated",
          message: "All AI agent activity has been halted. Reason: #{reason}",
          severity: "error",
          category: "ai"
        )
      rescue StandardError => e
        Rails.logger.error "[KillSwitch] Failed to notify users: #{e.message}"
      end
    end
  end
end
