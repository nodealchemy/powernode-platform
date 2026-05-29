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
          base = params[:base_branch] || mission.base_branch || mission.repository&.default_branch || "main"

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
              url = service.preview_url(port)
              mission.update!(deployed_url: url)
              orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
              orchestrator.advance!(result: { deployed_url: url, stub: true })
              render_success(deployment: { port: port, url: url, status: "stub", note: e.message }, mission: mission.reload.mission_details)
            end
          else
            url = service.preview_url(port)
            mission.update!(deployed_url: url)
            orchestrator = ::Ai::Missions::OrchestratorService.new(mission: mission)
            orchestrator.advance!(result: { deployed_url: url, stub: true })
            render_success(deployment: { port: port, url: url, status: "stub" }, mission: mission.reload.mission_details)
          end
        rescue ::Ai::Missions::AppLaunchService::LaunchError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/create_pr
        def create_pr
          mission = find_mission!
          return unless mission

          head = params[:head] || mission.branch_name
          base = params[:base] || mission.base_branch || mission.repository&.default_branch || "main"
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

        # GET /api/v1/ai/missions/:id/task_graph
        def task_graph
          mission = find_mission!
          return unless mission

          unless mission.ralph_loop
            render_success(task_graph: { nodes: [], edges: [] })
            return
          end

          tasks = mission.ralph_loop.ralph_tasks.includes(:executor).ordered

          nodes = tasks.map do |task|
            {
              id: task.id,
              task_key: task.task_key,
              description: task.description&.truncate(100),
              status: task.status,
              execution_type: task.execution_type,
              priority: task.priority,
              position: task.position,
              dependencies: task.dependencies || [],
              executor_type: task.executor_type,
              executor_name: task.executor&.try(:name),
              phase: task.metadata&.dig("phase"),
              metadata: task.metadata
            }
          end

          edges = tasks.flat_map do |task|
            (task.dependencies || []).filter_map do |dep_key|
              source_task = tasks.find { |t| t.task_key == dep_key }
              next unless source_task

              {
                id: "#{source_task.id}-#{task.id}",
                source: source_task.id,
                target: task.id
              }
            end
          end

          render_success(task_graph: { nodes: nodes, edges: edges })
        end

        # POST /api/v1/ai/missions/:id/save_as_template
        def save_as_template
          mission = find_mission!
          return unless mission

          template = mission.save_as_template!(
            name: params[:name],
            description: params[:description]
          )
          render_success(template: template.template_details)
        rescue StandardError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/missions/:id/compose_plan
        #
        # Infrastructure missions: returns the rich provisioning plan
        # (cost / topology / risk) sourced from PlanComposerService. Reuses
        # the cached plan when one already exists for the mission so the
        # deep-link page (`/app/system/provision?mission_id=…`) shows the
        # same data the chat already presented, no extra LLM cost.
        #
        # Other mission types: falls through to the legacy
        # SkillCompositionService task graph.
        def compose_plan
          mission = find_mission!
          return unless mission

          if mission.mission_type.to_s == "infrastructure"
            return compose_provisioning_plan(mission)
          end

          compose_skill_plan(mission)
        end

        private

        def compose_provisioning_plan(mission)
          plan = existing_provisioning_plan(mission) || compose_new_provisioning_plan(mission)
          return unless plan # error already rendered by composer

          snapshot = ::Ai::Provisioning::PlanSnapshotService
                       .new(account: current_account).snapshot(plan: plan)
          render_success(plan: snapshot.merge(mission_id: mission.id))
        end

        # Look up the plan referenced by `mission.configuration["plan"]["plan_id"]`
        # — set by the chat-tool path when it composes. Avoids re-running the LLM.
        # Runs a lazy compaction pass to fold any redundant provisioning clusters
        # that pre-date the collapse fix, so operators see a clean plan even if
        # the cached version was composed before the collapse logic existed.
        def existing_provisioning_plan(mission)
          plan_id = mission.configuration&.dig("plan", "plan_id")
          return nil if plan_id.blank?
          plan = ::Ai::GoalPlan.find_by(id: plan_id)
          return nil unless plan

          ::Ai::Provisioning::PlanComposerService
            .new(account: current_account, mission: mission)
            .compact_existing_plan!(plan)
          plan.reload
        rescue StandardError => e
          Rails.logger.warn("[MissionsController] lazy plan compaction failed: #{e.class}: #{e.message}")
          plan
        end

        def compose_new_provisioning_plan(mission)
          # Hybrid routing (shared with the worker-job + concierge paths):
          # recognized provisioning scenarios -> PlanComposerService, novel/general
          # intents -> MissionComposer. Only reached when no cached plan exists.
          composer = ::Ai::Missions::ComposerRouter.new(
            account: current_account, mission: mission
          ).select
          result = composer.compose!

          if result.is_a?(Hash) && result[:clarification_needed]
            render_error(result[:message] || "Multiple providers configured — clarify before composing",
                         :unprocessable_content,
                         details: result.except(:clarification_needed))
            return nil
          end

          unless result
            # Both composers expose cap_exceeded_payload (set when the LLM cost
            # cap gates composition); surface the upgrade message when present.
            render_error(composer.cap_exceeded_payload ? "LLM cost cap exceeded" : "Plan composition returned no plan",
                         :unprocessable_content)
            return nil
          end

          result
        rescue ::Ai::Provisioning::PlanComposerService::BriefMissingError,
               ::Ai::Provisioning::PlanComposerService::AgentMissingError,
               ::Ai::Missions::MissionComposer::CompositionError => e
          render_error(e.message, :unprocessable_content)
          nil
        end

        def compose_skill_plan(mission)
          llm_client = nil
          model = nil
          if mission.configuration&.dig("reasoning", "mode") == "star"
            credential = current_account.ai_provider_credentials
                           .joins(:provider).where(ai_providers: { is_active: true })
                           .where(is_active: true).first
            if credential
              agent = current_account.ai_agents.active.first
              llm_client = agent ? ::WorkerLlmClient.new(agent_id: agent.id) : nil
              model = credential.provider.default_model
            end
          end

          service = ::Ai::Missions::SkillCompositionService.new(
            mission: mission, llm_client: llm_client, model: model
          )
          plan = service.compose!
          render_success(plan: plan)
        rescue ::Ai::Missions::SkillCompositionService::CompositionError => e
          render_error(e.message, :unprocessable_content)
        end

        public

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
          params.permit(
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
