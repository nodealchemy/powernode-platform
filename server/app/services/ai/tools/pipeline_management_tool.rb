# frozen_string_literal: true

module Ai
  module Tools
    class PipelineManagementTool < BaseTool
      REQUIRED_PERMISSION = "git.pipelines.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "get_pipeline_status", mutating: false,
                                            returns: "the run's status and conclusion only",
                                            refuses: "pipeline_id is not a CI run in one of this account's git repositories",
                                            see_also: { "list_pipelines" => "finding CI run ids" }
      declare_action "list_pipelines", mutating: false, paginated: true,
                                       returns: "id, name, status, conclusion, repository_id, ref, sha, run number and timings per pipeline run, newest first",
                                       refuses: "repository_id names a repository outside this account"
      declare_action "trigger_pipeline", mutating: true,
                                         returns: "pipeline_id, the new run_id, the run status, and queued (false when the worker service was unreachable)",
                                         refuses: [
                                           "pipeline_id is missing",
                                           "no Devops::Pipeline with that id exists in this account",
                                           "the pipeline is inactive"
                                         ]

      def self.definition
        {
          name: "pipeline_management",
          description: "Trigger, list, or check status of DevOps pipelines",
          parameters: {
            action: { type: "string", required: true, description: "Action: trigger_pipeline, list_pipelines, get_pipeline_status" },
            pipeline_id: { type: "string", required: false },
            repository_id: { type: "string", required: false },
            branch: { type: "string", required: false }
          }
        }
      end

      def self.action_definitions
        {
          "trigger_pipeline" => {
            description: "Start a manual run of a DevOps pipeline definition (a Devops::Pipeline, not a CI run from list_pipelines). " \
                         "It creates a pending run and queues Devops::PipelineExecutionJob on the worker. " \
                         "The job is queued with simulate: true, so steps are simulated rather than executed by real handlers.",
            parameters: {
              pipeline_id: { type: "string", required: true, description: "Devops::Pipeline ID to run" }
            }
          },
          "list_pipelines" => {
            description: "List CI pipeline runs synced from the account's git repositories, optionally for one repository.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Only this repository's runs" }
            }.merge(PAGINATION_PARAMETERS)
          },
          "get_pipeline_status" => {
            description: "Get the status and conclusion of one CI pipeline run synced from a git repository (a Devops::GitPipeline). " \
                         "The id is a CI run id as listed by list_pipelines, not a Devops::Pipeline definition id.",
            parameters: {
              pipeline_id: { type: "string", required: true, description: "Devops::GitPipeline (CI run) ID" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "trigger_pipeline" then trigger_pipeline(params)
        when "list_pipelines" then list_pipelines(params)
        when "get_pipeline_status" then get_pipeline_status(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def trigger_pipeline(params)
        pipeline_id = params[:pipeline_id]
        return { success: false, error: "trigger_pipeline requires pipeline_id" } if pipeline_id.blank?

        pipeline = account.devops_pipelines.find(pipeline_id)
        return { success: false, error: "Cannot trigger inactive pipeline #{pipeline.id}" } unless pipeline.is_active?

        # Mirror Devops::PipelinesController#trigger: create a pending run, then
        # queue the real execution job via the worker (no fabricated success).
        run = pipeline.runs.create!(
          status: :pending,
          trigger_type: :manual,
          trigger_context: { source: "mcp_tool", agent_id: agent&.id }.compact,
          triggered_by: user
        )

        queued =
          begin
            WorkerJobService.enqueue_job(
              "Devops::PipelineExecutionJob",
              args: [ run.id, { simulate: true, step_delay: 3 } ],
              queue: "devops_high"
            )
            true
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn("[pipeline_management] worker service unavailable: #{e.message}")
            false
          end

        {
          success: true,
          pipeline_id: pipeline.id,
          run_id: run.id,
          status: run.status,
          queued: queued,
          message: queued ? "Pipeline run #{run.id} queued for execution" : "Pipeline run #{run.id} created but worker service unavailable"
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Pipeline not found" }
      end

      def list_pipelines(params)
        scope = Devops::GitPipeline.joins(:repository).where(git_repositories: { account_id: account.id })
        scope = scope.where(git_repository_id: account.git_repositories.find(params[:repository_id]).id) if params[:repository_id].present?

        paginated_result(:pipelines, scope, params) do |pipeline|
          { id: pipeline.id, name: pipeline.name, status: pipeline.status, conclusion: pipeline.conclusion,
            repository_id: pipeline.git_repository_id, ref: pipeline.ref, sha: pipeline.sha,
            run_number: pipeline.run_number, started_at: pipeline.started_at, completed_at: pipeline.completed_at }
        end
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Repository not found" }
      end

      def get_pipeline_status(params)
        pipeline = Devops::GitPipeline.joins(:repository)
                                       .where(git_repositories: { account_id: account.id })
                                       .find(params[:pipeline_id])
        { success: true, status: pipeline.status, conclusion: pipeline.conclusion }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Pipeline not found" }
      end
    end
  end
end
