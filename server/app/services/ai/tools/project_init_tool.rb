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
            description: { type: "string", required: false, description: "Repository description" }
          }
        }
      end

      protected

      def call(params)
        service = Ai::ProjectInitializationService.new(
          account: account,
          repo_name: params[:repo_name],
          description: params[:description]
        )
        service.call
      end
    end
  end
end
