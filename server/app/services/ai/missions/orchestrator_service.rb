# frozen_string_literal: true

module Ai
  module Missions
    class OrchestratorService
      class OrchestrationError < StandardError; end

      CLEANUP_PHASES = %w[completed cancelled].freeze

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      def start!
        raise OrchestrationError, "Mission must be in draft status to start" unless mission.status == "draft"
        raise OrchestrationError, "Mission must have an objective" if mission.objective.blank? && mission.mission_type == "development"

        create_conversation! if mission.conversation_id.blank?

        first_phase = mission.phases_for_type.first
        ActiveRecord::Base.transaction do
          mission.update!(status: "active", started_at: Time.current)
          transition_to_phase!(first_phase)
        end

        dispatch_phase_job!

        mission
      end

      def advance!(result: {}, expected_phase: nil)
        # Guard against stale Sidekiq retries: if the caller specifies
        # which phase it expects, reject the advance if the mission has
        # already moved past that phase.
        if expected_phase.present? && mission.current_phase != expected_phase
          Rails.logger.warn(
            "Stale advance rejected for mission #{mission.id}: " \
            "expected phase #{expected_phase}, current phase #{mission.current_phase}"
          )
          return mission
        end

        record_phase_exit(result)

        next_phase = determine_next_phase
        if next_phase.nil? || next_phase == "completed"
          complete_mission!(result)
        else
          transition_to_phase!(next_phase)
          dispatch_phase_job! unless mission.awaiting_approval?
        end

        mission
      end

      def handle_approval!(gate:, user:, decision:, comment: nil, selected_feature: nil, prd_modifications: nil)
        approval = mission.approvals.create!(
          account: account,
          user: user,
          gate: gate_for_phase(gate),
          decision: decision,
          comment: comment,
          metadata: { selected_feature: selected_feature, prd_modifications: prd_modifications }.compact
        )

        if decision == "approved"
          if selected_feature.present?
            mission.update!(selected_feature: selected_feature)
          end

          advance!(result: { approval_id: approval.id })
        else
          handle_rejection!(gate: mission.current_phase, comment: comment)
        end

        mission
      end

      def cancel!(reason: nil)
        mission.update!(
          status: "cancelled",
          error_message: reason,
          completed_at: Time.current
        )
        dispatch_cleanup_job!
        mission
      end

      def pause!
        raise OrchestrationError, "Mission must be active to pause" unless mission.status == "active"

        mission.update!(status: "paused")
        mission
      end

      def resume!
        raise OrchestrationError, "Mission must be paused to resume" unless mission.status == "paused"

        mission.update!(status: "active")
        dispatch_phase_job! unless mission.awaiting_approval?
        mission
      end

      def retry_phase!
        raise OrchestrationError, "Mission must be active or failed" unless %w[active failed].include?(mission.status)

        mission.update!(status: "active", error_message: nil, error_details: {})
        dispatch_phase_job!
        mission
      end

      private

      def transition_to_phase!(phase)
        mission.update!(current_phase: phase)
        record_phase_entry(phase)
      end

      def record_phase_entry(phase)
        history = mission.phase_history || []
        history << { phase: phase, entered_at: Time.current.iso8601 }
        mission.update!(phase_history: history)
      end

      def record_phase_exit(result)
        history = mission.phase_history || []
        current_entry = history.last
        if current_entry
          current_entry["exited_at"] = Time.current.iso8601
          current_entry["result"] = result if result.present?
          mission.update!(phase_history: history)
        end
      end

      def determine_next_phase
        phases = mission.phases_for_type
        current_index = phases.index(mission.current_phase)
        return nil unless current_index

        next_index = current_index + 1
        return nil if next_index >= phases.length

        next_phase = phases[next_index]

        skip_config = mission.phase_config["skip_phases"] || []
        while skip_config.include?(next_phase) && next_index < phases.length - 1
          next_index += 1
          next_phase = phases[next_index]
        end

        next_phase
      end

      def dispatch_phase_job!
        phase = mission.current_phase
        return if mission.awaiting_approval?

        job_class = job_class_for_phase(phase)
        return unless job_class

        Rails.logger.info("Dispatching #{job_class} for mission #{mission.id}")
        WorkerJobService.enqueue_job(job_class, args: [{
          "mission_id" => mission.id,
          "account_id" => account.id
        }], queue: "ai_execution")
      end

      def dispatch_cleanup_job!
        Rails.logger.info("Dispatching cleanup for mission #{mission.id}")
        WorkerJobService.enqueue_job("AiMissionCleanupJob", args: [{
          "mission_id" => mission.id,
          "account_id" => account.id
        }], queue: "maintenance")
      end

      def complete_mission!(result)
        mission.update!(
          status: "completed",
          current_phase: "completed",
          completed_at: Time.current
        )
        dispatch_cleanup_job!
      end

      def handle_rejection!(gate:, comment:)
        rollback_phase = resolve_rejection_target(gate)
        if rollback_phase
          transition_to_phase!(rollback_phase)
          dispatch_phase_job!
        end
      end

      def resolve_rejection_target(gate)
        if mission.mission_template.present?
          mission.mission_template.rejection_mapping_for(gate)
        end
      end

      def job_class_for_phase(phase)
        custom = find_custom_phase_config(phase)
        custom&.dig("job_class")
      end

      def find_custom_phase_config(phase_key)
        if mission.custom_phases.present?
          mission.custom_phases.find { |p| p["key"] == phase_key }
        elsif mission.mission_template.present?
          mission.mission_template.phases&.find { |p| p["key"] == phase_key }
        end
      end

      def gate_for_phase(phase)
        config = find_custom_phase_config(phase)
        config&.dig("gate_name") || phase
      end

      def create_conversation!
        return unless defined?(Ai::Conversation)

        provider = account.ai_providers.first
        return unless provider

        conversation = account.ai_conversations.create!(
          user: mission.created_by,
          ai_provider_id: provider.id,
          title: "Mission: #{mission.name}",
          status: "active",
          conversation_type: "agent",
          message_count: 0,
          total_tokens: 0,
          total_cost: 0
        )
        mission.update!(conversation_id: conversation.id)
      rescue StandardError => e
        Rails.logger.warn("Failed to create mission conversation: #{e.message}")
      end
    end
  end
end
