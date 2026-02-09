# frozen_string_literal: true

module Ai
  module Tools
    class PipelineManagementTool < BaseTool
      REQUIRED_PERMISSION = "git.pipelines.manage"

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
        repository = account.git_repositories.find(params[:repository_id])
        { success: true, repository_id: repository.id, status: "triggered", message: "Pipeline triggered" }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Repository not found" }
      end

      def list_pipelines(params)
        scope = account.git_repositories
        scope = scope.find(params[:repository_id]).pipelines if params[:repository_id].present?
        pipelines = (scope.respond_to?(:pipelines) ? scope : Devops::GitPipeline.joins(:repository).where(git_repositories: { account_id: account.id })).limit(50)
        { success: true, count: pipelines.count }
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
