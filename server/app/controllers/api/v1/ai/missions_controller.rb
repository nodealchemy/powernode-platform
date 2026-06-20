# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MissionsController < ApplicationController
        rescue_from WorkerJobService::WorkerServiceError, with: :handle_worker_service_error

        before_action :authorize_read!, only: [:index, :show, :task_graph]
        before_action :authorize_manage!, only: [
          :create, :update, :destroy, :start, :approve, :reject,
          :pause, :resume, :cancel, :retry_phase, :deploy_callback, :analyze_repo,
          :advance, :create_branch, :generate_prd, :run_tests, :deploy, :create_pr, :cleanup_deployment,
          :save_as_template, :compose_plan
        ]
        before_action :authorize_read!, only: [:test_status]

        include ::Ai::Missions::LifecycleActions
        include ::Ai::Missions::OperationActions
        include ::Ai::Missions::PlanCompositionActions

        # GET /api/v1/ai/missions
        def index
          missions = current_account.ai_missions
            .includes(:created_by, :repository, :team)
            .order(created_at: :desc)

          missions = missions.where(status: params[:status]) if params[:status].present?
          missions = missions.where(mission_type: params[:mission_type]) if params[:mission_type].present?

          render_success(missions: missions.map(&:mission_summary))
        end

        # POST /api/v1/ai/missions
        def create
          mission = current_account.ai_missions.new(mission_params)
          mission.created_by = current_user

          if mission.save
            render_success(mission: mission.mission_details, status: :created)
          else
            render_error(mission.errors.full_messages.join(", "), :unprocessable_content)
          end
        end

        # GET /api/v1/ai/missions/:id
        def show
          mission = find_mission!
          return unless mission

          render_success(mission: mission.mission_details)
        end

        # PATCH /api/v1/ai/missions/:id
        def update
          mission = find_mission!
          return unless mission

          if mission.update(mission_params)
            render_success(mission: mission.mission_details)
          else
            render_error(mission.errors.full_messages.join(", "), :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/missions/:id
        def destroy
          mission = find_mission!
          return unless mission

          if mission.terminal?
            mission.destroy!
            render_success(deleted: true)
          else
            render_error("Can only delete completed, failed, or cancelled missions", :unprocessable_content)
          end
        end

        private

        def authorize_read!
          unless has_permission?("ai.missions.read")
            render_error("Forbidden", :forbidden)
          end
        end

        def authorize_manage!
          unless has_permission?("ai.missions.manage")
            render_error("Forbidden", :forbidden)
          end
        end

        def find_mission!
          current_account.ai_missions.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Mission not found", :not_found)
          nil
        end

        def find_mission_by_id(id)
          current_account.ai_missions.find(id)
        rescue ActiveRecord::RecordNotFound
          render_error("Mission not found", :not_found)
          nil
        end

        def dismiss_approval_notifications(mission)
          Notification.where(
            account: current_account,
            notification_type: "ai_plan_review"
          ).not_dismissed.where(
            "metadata->>'mission_id' = ?", mission.id
          ).find_each(&:dismiss!)
        rescue StandardError => e
          Rails.logger.warn("Failed to dismiss approval notifications for mission #{mission.id}: #{e.message}")
        end

        def handle_worker_service_error(exception)
          render_error("Worker service unavailable: #{exception.message}", :service_unavailable)
        end

        def mission_params
          # Worker callbacks (e.g. fleet-phase report_failure) send the payload
          # nested under :mission; UI and API clients send top-level. Accept both.
          source = params[:mission].is_a?(ActionController::Parameters) ? params.require(:mission) : params
          source.permit(
            :name, :description, :mission_type, :objective,
            :repository_id, :team_id, :base_branch, :risk_contract_id,
            :status, :current_phase, :branch_name, :error_message,
            :ralph_loop_id, :review_state_id, :conversation_id,
            :deployed_port, :deployed_url, :deployed_container_id,
            :pr_number, :pr_url, :mission_template_id,
            phase_config: {}, configuration: {}, metadata: {},
            analysis_result: {}, selected_feature: {},
            prd_json: {}, test_result: {}, review_result: {},
            error_details: {},
            custom_phases: [:key, :label, :description, :requires_approval, :job_class,
                            :estimated_duration_minutes, :skip_allowed, :order]
          )
        end
      end
    end
  end
end
