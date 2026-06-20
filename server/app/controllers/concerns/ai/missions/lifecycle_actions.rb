# frozen_string_literal: true

module Ai
  module Missions
    module LifecycleActions
      extend ActiveSupport::Concern

      # POST /api/v1/ai/missions/:id/start
      def start
        mission = find_mission!
        return unless mission

        service = ::Ai::Missions::OrchestratorService.new(mission: mission)
        service.start!
        render_success(mission: mission.reload.mission_details)
      rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
        render_error(e.message, :unprocessable_content)
      end

      # POST /api/v1/ai/missions/:id/approve
      # Phase-to-gate translation lives on Ai::MissionApproval — single
      # source of truth shared with OrchestratorService and any future
      # caller that creates approvals.
      def approve
        handle_approval_decision("approved")
      end

      # POST /api/v1/ai/missions/:id/reject
      def reject
        handle_approval_decision("rejected")
      end

      # POST /api/v1/ai/missions/:id/pause
      def pause
        mission = find_mission!
        return unless mission

        service = ::Ai::Missions::OrchestratorService.new(mission: mission)
        service.pause!
        render_success(mission: mission.reload.mission_details)
      rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
        render_error(e.message, :unprocessable_content)
      end

      # POST /api/v1/ai/missions/:id/resume
      def resume
        mission = find_mission!
        return unless mission

        service = ::Ai::Missions::OrchestratorService.new(mission: mission)
        service.resume!
        render_success(mission: mission.reload.mission_details)
      rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
        render_error(e.message, :unprocessable_content)
      end

      # POST /api/v1/ai/missions/:id/cancel
      def cancel
        mission = find_mission!
        return unless mission

        service = ::Ai::Missions::OrchestratorService.new(mission: mission)
        service.cancel!(reason: params[:reason])
        render_success(mission: mission.reload.mission_details)
      end

      # POST /api/v1/ai/missions/:id/retry
      def retry_phase
        mission = find_mission!
        return unless mission

        service = ::Ai::Missions::OrchestratorService.new(mission: mission)
        service.retry_phase!
        render_success(mission: mission.reload.mission_details)
      rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
        render_error(e.message, :unprocessable_content)
      end

      private

      # Shared body of approve/reject so the gate-resolution + already-past
      # guard live in one place.
      def handle_approval_decision(decision)
        mission = find_mission!
        return unless mission

        gate = ::Ai::MissionApproval.gate_for_phase(mission.current_phase, mission: mission)

        unless ::Ai::MissionApproval::GATES.include?(gate.to_s)
          # Phase doesn't have an approval gate (automated phase like
          # execute / verify / adapting, or a stale UI click after the
          # mission already advanced past review). Idempotent response —
          # no validation error in the rails log, no scary 422 on the
          # frontend, just a clear "already past approval" reply.
          render_error(
            "Mission is in phase '#{mission.current_phase}', which does not require approval",
            :conflict,
            code: "NO_APPROVAL_GATE"
          )
          return
        end

        service = ::Ai::Missions::OrchestratorService.new(mission: mission)
        service.handle_approval!(
          gate: gate,
          user: current_user,
          decision: decision,
          comment: params[:comment],
          selected_feature: decision == "approved" ? params[:selected_feature] : nil,
          prd_modifications: decision == "approved" ? params[:prd_modifications] : nil
        )
        dismiss_approval_notifications(mission)
        render_success(mission: mission.reload.mission_details)
      rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
        render_error(e.message, :unprocessable_content)
      end
    end
  end
end
