# frozen_string_literal: true

module Ai
  module Missions
    class RepoAnalysisService
      class AnalysisError < StandardError; end

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      def analyze!
        repository = mission.repository
        raise AnalysisError, "No repository linked to mission" unless repository

        credential = find_credential(repository)
        raise AnalysisError, "No git credentials found for repository" unless credential

        client = Devops::Git::ApiClient.for(credential)
        owner = repository.owner
        repo_name = repository.name

        analysis_data = gather_repo_data(client, owner, repo_name)
        suggestions = generate_suggestions(analysis_data)

        result = {
          tech_stack: analysis_data[:tech_stack],
          structure: analysis_data[:structure],
          recent_activity: analysis_data[:recent_activity],
          feature_suggestions: suggestions
        }

        mission.update!(
          analysis_result: result,
          feature_suggestions: suggestions
        )

        result
      end

      private

      def find_credential(repository)
        account.git_provider_credentials
          .joins(:provider)
          .where(git_providers: { provider_type: repository.provider_type })
          .first
      end

      def gather_repo_data(client, owner, repo_name)
        tech_stack = {}
        structure = {}
        recent_activity = {}

        package_json = client.get_file_content(owner, repo_name, "package.json")

        if package_json && package_json[:content]
          parsed = JSON.parse(package_json[:content]) rescue {}
          tech_stack["node"] = true
          tech_stack["dependencies"] = (parsed["dependencies"] || {}).keys.first(20)
          tech_stack["dev_dependencies"] = (parsed["devDependencies"] || {}).keys.first(10)
        end

        begin
          repo_info = client.get_repository(owner, repo_name)
          default_branch = repo_info["default_branch"] || "main"
          tree = client.get_tree(owner, repo_name, default_branch, recursive: false)
          if tree
            structure["entries"] = (tree[:entries] || []).map { |e| { path: e[:path], type: e[:type] } }.first(50)
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to get repo tree: #{e.message}")
        end

        begin
          commits = client.list_commits(owner, repo_name, per_page: 10)
          recent_activity["recent_commits"] = (commits || []).first(10).map do |c|
            commit_data = c.is_a?(Hash) ? c : {}
            {
              sha: commit_data["sha"]&.to_s&.first(8),
              message: (commit_data.dig("commit", "message") || commit_data["message"] || "").to_s.first(100)
            }
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to get commits: #{e.message}")
        end

        begin
          issues = client.list_issues(owner, repo_name, state: "open")
          recent_activity["open_issues"] = (issues || []).first(10).map do |i|
            { title: i["title"], number: i["number"] }
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to get issues: #{e.message}")
        end

        {
          tech_stack: tech_stack,
          structure: structure,
          recent_activity: recent_activity
        }
      end

      def generate_suggestions(analysis_data)
        suggestions = []

        # Primary suggestion from mission objective
        if mission.objective.present?
          suggestions << {
            title: mission.name,
            description: mission.objective,
            complexity: "medium",
            files_affected: []
          }
        end

        if analysis_data[:tech_stack]["dependencies"]&.any?
          suggestions << {
            title: "Add automated testing",
            description: "Set up comprehensive test coverage for the project",
            complexity: "medium",
            files_affected: ["package.json", "jest.config.js"]
          }
        end

        if analysis_data[:recent_activity]["open_issues"]&.any?
          analysis_data[:recent_activity]["open_issues"].first(3).each do |issue|
            suggestions << {
              title: "Fix: #{issue[:title]}",
              description: "Address open issue ##{issue[:number]}",
              complexity: "medium",
              files_affected: []
            }
          end
        end

        suggestions.first(5)
      end
    end
  end
end
