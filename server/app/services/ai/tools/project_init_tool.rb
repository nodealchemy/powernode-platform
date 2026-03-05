# frozen_string_literal: true

module Ai
  module Tools
    class ProjectInitTool < BaseTool
      REQUIRED_PERMISSION = "ai.workflows.create"

      def self.definition
        {
          name: "create_gitea_repository",
          description: "Create a new Gitea repository with project scaffold",
          parameters: {
            repo_name: { type: "string", required: true, description: "Repository name" },
            description: { type: "string", required: false, description: "Repository description" },
            organization: { type: "string", required: false, description: "Organization name to create the repository under (omit for personal namespace)" }
          }
        }
      end

      protected

      def call(params)
        service = Ai::ProjectInitializationService.new(
          account: account,
          repo_name: params[:repo_name],
          description: params[:description],
          organization: params[:organization]
        )
        service.call
      end
    end
  end
end
