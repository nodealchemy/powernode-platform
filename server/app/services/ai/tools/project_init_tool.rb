# frozen_string_literal: true

module Ai
  module Tools
    class ProjectInitTool < BaseTool
      REQUIRED_PERMISSION = "devops.ci.write"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "create_gitea_repository", mutating: true

      def self.definition
        {
          name: "create_gitea_repository",
          description: "Create a new Gitea repository with project scaffold",
          parameters: {
            repo_name: { type: "string", required: true, description: "Repository name" },
            description: { type: "string", required: false, description: "Repository description" },
            organization: { type: "string", required: false, description: "Organization name to create the repository under (omit for personal namespace)" },
            private: { type: "boolean", required: false, description: "Whether the repository should be private (default: true)" }
          }
        }
      end

      def self.action_definitions
        {
          "create_gitea_repository" => {
            description: "Create a new Gitea repository with project scaffold",
            parameters: {
              repo_name: { type: "string", required: true, description: "Repository name" },
              description: { type: "string", required: false, description: "Repository description" },
              organization: { type: "string", required: false, description: "Organization name to create the repository under (omit for personal namespace)" },
              private: { type: "boolean", required: false, description: "Whether the repository should be private (default: true)" }
            }
          }
        }
      end

      protected

      def call(params)
        service = Ai::ProjectInitializationService.new(
          account: account,
          repo_name: params[:repo_name],
          description: params[:description],
          organization: params[:organization],
          private: params.fetch(:private, true)
        )
        service.call
      end
    end
  end
end
