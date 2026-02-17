# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MissionsController < ApplicationController
        before_action :authorize_read!, only: [:index, :show]
        before_action :authorize_manage!, only: [
          :create, :update, :destroy, :start, :approve, :reject,
          :pause, :resume, :cancel, :retry_phase, :deploy_callback, :analyze_repo,
          :advance, :create_branch, :generate_prd, :run_tests, :deploy, :create_pr, :cleanup_deployment
        ]
        before_action :authorize_read!, only: [:test_status]

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
        def approve
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::OrchestratorService.new(mission: mission)
          service.handle_approval!(
            gate: mission.current_phase,
            user: current_user,
            decision: "approved",
            comment: params[:comment],
            selected_feature: params[:selected_feature],
            prd_modifications: params[:prd_modifications]
          )
          render_success(mission: mission.reload.mission_details)
        rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/reject
        def reject
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::OrchestratorService.new(mission: mission)
          service.handle_approval!(
            gate: mission.current_phase,
            user: current_user,
            decision: "rejected",
            comment: params[:comment]
          )
          render_success(mission: mission.reload.mission_details)
        rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
          render_error(e.message, :unprocessable_content)
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

        # POST /api/v1/ai/missions/:id/deploy_callback
        def deploy_callback
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::AppLaunchService.new(mission: mission)

          if params[:status] == "success"
            service.record_deployment!(
              container_id: params[:container_id],
              url: params[:url]
            )
            orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
            orchestrator.advance!(result: { deployed_url: params[:url] })
          else
            mission.update!(error_message: "Deployment failed: #{params[:error]}")
          end

          render_success(received: true)
        end

        # POST /api/v1/ai/missions/analyze_repo
        def analyze_repo
          repository_id = params[:repository_id]
          mission_id = params[:mission_id]

          if mission_id.present?
            mission = find_mission_by_id(mission_id)
            return unless mission
          else
            mission = current_account.ai_missions.new(
              name: "Repo Analysis",
              mission_type: "research",
              status: "active",
              created_by: current_user
            )
          end

          if repository_id.present? && mission.repository_id.blank?
            repo = current_account.git_repositories.find_by(id: repository_id)
            mission.repository = repo if repo
          end

          service = ::Ai::Missions::RepoAnalysisService.new(mission: mission)
          result = service.analyze!
          render_success(analysis: result)
        rescue ::Ai::Missions::RepoAnalysisService::AnalysisError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/advance
        def advance
          mission = find_mission!
          return unless mission

          orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
          orchestrator.advance!(
            result: params[:result]&.to_unsafe_h || {},
            expected_phase: params[:expected_phase]
          )
          render_success(mission: mission.reload.mission_details)
        rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/create_branch
        def create_branch
          mission = find_mission!
          return unless mission

          branch_name = params[:branch_name] || "mission/#{mission.id[0..7]}-#{mission.name.parameterize}"
          base = params[:base_branch] || mission.base_branch || "main"

          service = ::Ai::Missions::PrManagementService.new(mission: mission)
          result = service.create_branch!(base: base, name: branch_name)
          render_success(branch: { name: branch_name, base: base, result: result })
        rescue ::Ai::Missions::PrManagementService::PrError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/generate_prd
        def generate_prd
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::PrdGenerationService.new(mission: mission)
          prd = service.generate!

          orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
          orchestrator.advance!(result: { prd: prd })
          render_success(mission: mission.reload.mission_details)
        rescue ::Ai::Missions::PrdGenerationService::PrdGenerationError => e
          render_error(e.message, :unprocessable_content)
        rescue StandardError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/run_tests
        def run_tests
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::TestRunnerService.new(mission: mission)
          result = service.trigger!
          render_success(test_run: { run_id: result[:run_id], status: result[:status], method: result[:method] })
        rescue ::Ai::Missions::TestRunnerService::TestRunnerError => e
          render_error(e.message, :unprocessable_content)
        rescue StandardError => e
          render_error(e.message, :unprocessable_content)
        end

        # GET /api/v1/ai/missions/:id/test_status
        def test_status
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::TestRunnerService.new(mission: mission)
          result = service.check_status

          lifecycle_status = case result[:status]
                             when "completed" then "completed"
                             when "failed" then "failed"
                             when "running" then "running"
                             else result[:status] || "unknown"
                             end

          render_success(test_result: {
            status: lifecycle_status,
            passed: result[:passed],
            run_id: mission.test_result&.dig("run_id"),
            results: result[:results] || mission.test_result
          })
        end

        # POST /api/v1/ai/missions/:id/deploy
        def deploy
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::AppLaunchService.new(mission: mission)
          port = service.allocate_port!

          if mission.repository.present? && mission.branch_name.present?
            begin
              service.launch!(branch: mission.branch_name)
              render_success(deployment: { port: port, status: "launching", branch: mission.branch_name })
            rescue ::Ai::Missions::AppLaunchService::LaunchError => e
              # Workflow not available — fall back to stub deployment and advance
              Rails.logger.warn("Deploy workflow failed (#{e.message}), using stub deployment")
              url = "http://localhost:#{port}"
              mission.update!(deployed_url: url)
              orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
              orchestrator.advance!(result: { deployed_url: url, stub: true })
              render_success(deployment: { port: port, url: url, status: "stub", note: e.message })
            end
          else
            url = "http://localhost:#{port}"
            mission.update!(deployed_url: url)
            orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
            orchestrator.advance!(result: { deployed_url: url, stub: true })
            render_success(deployment: { port: port, url: url, status: "stub" })
          end
        rescue ::Ai::Missions::AppLaunchService::LaunchError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/create_pr
        def create_pr
          mission = find_mission!
          return unless mission

          head = params[:head] || mission.branch_name
          base = params[:base] || mission.base_branch || "main"
          title = params[:title] || "Mission: #{mission.name}"
          body = params[:body] || "Automated PR from mission #{mission.id}\n\n#{mission.objective}"

          service = ::Ai::Missions::PrManagementService.new(mission: mission)
          result = service.create_pr!(head: head, base: base, title: title, body: body)
          render_success(pull_request: { pr_number: mission.reload.pr_number, pr_url: mission.pr_url, result: result })
        rescue ::Ai::Missions::PrManagementService::PrError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/cleanup_deployment
        def cleanup_deployment
          mission = find_mission!
          return unless mission

          service = ::Ai::Missions::AppLaunchService.new(mission: mission)
          service.cleanup!
          render_success(cleaned: true)
        rescue ::Ai::Missions::AppLaunchService::LaunchError => e
          render_error(e.message, :unprocessable_content)
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

        def mission_params
          params.permit(
            :name, :description, :mission_type, :objective,
            :repository_id, :team_id, :base_branch, :risk_contract_id,
            :status, :current_phase, :branch_name, :error_message,
            :ralph_loop_id, :review_state_id, :conversation_id,
            :deployed_port, :deployed_url, :deployed_container_id,
            :pr_number, :pr_url,
            phase_config: {}, configuration: {}, metadata: {},
            analysis_result: {}, selected_feature: {},
            prd_json: {}, test_result: {}, review_result: {},
            error_details: {}
          )
        end
      end
    end
  end
end
