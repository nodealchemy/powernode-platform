# frozen_string_literal: true

module Ai
  module Missions
    module OperationActions
      extend ActiveSupport::Concern

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
    end
  end
end
