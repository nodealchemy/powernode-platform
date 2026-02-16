# frozen_string_literal: true

module Ai
  module Git
    class GiteaIntegrationService
      attr_reader :repository_path, :gitea_repository, :worktree_manager

      def initialize(repository_path:, gitea_repository:, gitea_client: nil)
        @repository_path = repository_path
        @gitea_repository = gitea_repository
        @worktree_manager = Ai::Git::WorktreeManager.new(repository_path: repository_path)
        @gitea_client = gitea_client || build_gitea_client
      end

      # Push a branch and create a pull request on Gitea
      def push_and_create_pr(branch_name:, target_branch: "develop", title:, body: "")
        # Push the branch to remote
        push_result = worktree_manager.push_branch(branch_name: branch_name)
        unless push_result[:success]
          return { success: false, error: "Push failed: #{push_result[:error]}" }
        end

        # Create PR via Gitea API
        owner, repo = gitea_repository.split("/")
        pr_data = @gitea_client.create_pull_request(
          owner: owner,
          repo: repo,
          title: title,
          body: body,
          head: branch_name,
          base: target_branch
        )

        Rails.logger.info("[GiteaIntegration] Created PR ##{pr_data['number']}: #{title}")

        {
          success: true,
          pr_number: pr_data["number"],
          pr_url: pr_data["html_url"],
          branch: branch_name,
          target: target_branch
        }
      rescue StandardError => e
        Rails.logger.error("[GiteaIntegration] push_and_create_pr failed: #{e.message}")
        { success: false, error: e.message }
      end

      # Finalize a worktree session by pushing the integration branch and creating a PR
      def finalize_session_with_pr(session:, title: nil, body: nil)
        branch_name = session.integration_branch || session.branch_name
        title ||= "AI Session: #{session.description || session.id}"
        body ||= build_pr_body(session)

        push_and_create_pr(
          branch_name: branch_name,
          target_branch: session.configuration&.dig("target_branch") || "develop",
          title: title,
          body: body
        )
      end

      # Create individual PRs for each worktree in a session (manual merge strategy)
      def create_individual_prs(session:, target_branch: "develop")
        results = []

        session.worktrees.each do |worktree|
          branch_name = worktree["branch_name"] || worktree[:branch_name]
          next unless branch_name

          result = push_and_create_pr(
            branch_name: branch_name,
            target_branch: target_branch,
            title: "AI Worktree: #{branch_name}",
            body: "Automated PR from AI worktree session #{session.id}"
          )

          results << result.merge(worktree_branch: branch_name)
        end

        {
          success: results.all? { |r| r[:success] },
          prs: results
        }
      end

      # Configure branch protection rules on Gitea
      def setup_branch_protection(branches:, options: {})
        owner, repo = gitea_repository.split("/")
        results = []

        branches.each do |branch_pattern|
          result = @gitea_client.update_branch_protection(
            owner, repo, branch_pattern,
            enable_push: options.fetch(:enable_push, false),
            enable_merge_whitelist: options.fetch(:enable_merge_whitelist, true),
            required_approvals: options.fetch(:required_approvals, 1),
            enable_status_check: options.fetch(:enable_status_check, false),
            dismiss_stale_approvals: options.fetch(:dismiss_stale_approvals, true)
          )

          results << { branch: branch_pattern, success: true, data: result }
        rescue StandardError => e
          results << { branch: branch_pattern, success: false, error: e.message }
        end

        {
          success: results.all? { |r| r[:success] },
          rules: results
        }
      end

      private

      def build_gitea_client
        # Use existing Gitea API client if available
        if defined?(Devops::Git::GiteaApiClient)
          credential = Devops::GitCredential.find_by(provider_type: "gitea", status: "active")
          raise "No active Gitea credential found. Configure a Gitea credential first." unless credential

          Devops::Git::GiteaApiClient.new(credential)
        else
          raise "GiteaApiClient not available. Ensure devops/git/gitea_api_client.rb is loaded."
        end
      end

      def build_pr_body(session)
        lines = ["## AI Worktree Session"]
        lines << ""
        lines << "**Session ID**: #{session.id}"
        lines << "**Description**: #{session.description}" if session.description.present?
        lines << "**Created**: #{session.created_at}"
        lines << ""
        lines << "### Changes"
        lines << ""

        if session.respond_to?(:worktrees) && session.worktrees.present?
          session.worktrees.each do |wt|
            branch = wt["branch_name"] || wt[:branch_name]
            lines << "- `#{branch}`"
          end
        end

        lines << ""
        lines << "---"
        lines << "_Generated by Powernode AI Orchestration_"
        lines.join("\n")
      end
    end
  end
end
