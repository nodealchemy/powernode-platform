# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class ExperienceReplaysController < InternalBaseController
          # POST /api/v1/internal/ai/experience_replays/capture
          # Called by AiExperienceReplayCaptureJob to store replay from a completed execution
          def capture
            execution = ::Ai::AgentExecution.find(params[:execution_id])
            account = execution.account

            trajectory = params[:trajectory_id].present? ? ::Ai::Trajectory.find(params[:trajectory_id]) : nil

            service = ::Ai::Learning::ExperienceReplayService.new(account: account)
            replay = service.capture_from_execution(execution, trajectory: trajectory)

            if replay
              render_success(
                id: replay.id,
                execution_id: execution.id,
                captured: true
              )
            else
              render_success(captured: false, reason: "skipped_by_service")
            end
          rescue ActiveRecord::RecordNotFound => e
            render_error(e.message, status: :not_found)
          rescue StandardError => e
            Rails.logger.error "[ExperienceReplay] Capture failed for execution #{params[:execution_id]}: #{e.message}"
            render_error("Capture failed: #{e.message}", status: :unprocessable_content)
          end
        end
      end
    end
  end
end
