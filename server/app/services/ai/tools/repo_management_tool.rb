# frozen_string_literal: true

module Ai
  module Tools
    class RepoManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.workflows.update"

      def self.definition
        {
          name: "update_gitea_repository",
          description: "Update settings on an existing Gitea repository (visibility, description, archival, etc.)",
          parameters: {
            owner: { type: "string", required: true, description: "Repository owner (username or organization)" },
            repo: { type: "string", required: true, description: "Repository name" },
            private: { type: "boolean", required: false, description: "Set repository visibility (true = private, false = public)" },
            description: { type: "string", required: false, description: "Updated repository description" },
            archived: { type: "boolean", required: false, description: "Archive or unarchive the repository" },
            default_branch: { type: "string", required: false, description: "Change the default branch" }
          }
        }
      end

      protected

      def call(params)
        credential = find_gitea_credential
        return { success: false, error: "No active Gitea credential found" } unless credential

        client = Devops::Git::ApiClient.for(credential)

        options = {}
        options[:private] = params[:private] unless params[:private].nil?
        options[:description] = params[:description] if params[:description]
        options[:archived] = params[:archived] unless params[:archived].nil?
        options[:default_branch] = params[:default_branch] if params[:default_branch]

        return { success: false, error: "No settings to update" } if options.empty?

        result = client.update_repository(params[:owner], params[:repo], options)
        {
          success: true,
          repository: {
            name: result["name"],
            full_name: result["full_name"],
            private: result["private"],
            archived: result["archived"],
            default_branch: result["default_branch"],
            description: result["description"],
            url: result["html_url"]
          }
        }
      end

      private

      def find_gitea_credential
        gitea_provider = Devops::GitProvider.find_by(provider_type: "gitea")
        return nil unless gitea_provider

        account.git_provider_credentials
               .where(git_provider_id: gitea_provider.id, is_active: true)
               .order(is_default: :desc, created_at: :desc)
               .first
      end
    end
  end
end
