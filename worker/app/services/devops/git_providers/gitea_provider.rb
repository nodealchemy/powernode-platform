# frozen_string_literal: true

require_relative "base_provider"

module Devops
  module GitProviders
    # Gitea API integration
    # API Documentation: https://docs.gitea.com/api/1.20/
    class GiteaProvider < BaseProvider
      API_VERSION = "/api/v1"

      def provider_type
        :gitea
      end

      # =============================================================================
      # COMMIT STATUS
      # =============================================================================

      def create_commit_status(repo:, sha:, state:, context:, description:, target_url: nil)
        path = "#{API_VERSION}/repos/#{repo}/statuses/#{sha}"

        body = {
          state: map_status(state),
          context: context,
          description: description&.slice(0, 140)
        }
        body[:target_url] = target_url if target_url

        log_info("Creating commit status", repo: repo, sha: sha[0..7], state: state)
        request(:post, path, body: body)
      end

      def get_commit_statuses(repo:, sha:)
        path = "#{API_VERSION}/repos/#{repo}/commits/#{sha}/statuses"

        response = request(:get, path)
        response.map { |status| normalize_commit_status(status) }
      end

      # =============================================================================
      # PULL REQUESTS
      # =============================================================================

      def create_pull_request(repo:, title:, head:, base:, body: nil, draft: false)
        path = "#{API_VERSION}/repos/#{repo}/pulls"

        request_body = {
          title: title,
          head: head,
          base: base,
          body: body
        }

        log_info("Creating pull request", repo: repo, head: head, base: base)
        response = request(:post, path, body: request_body)
        normalize_pull_request(response)
      end

      def get_pull_request(repo:, number:)
        path = "#{API_VERSION}/repos/#{repo}/pulls/#{number}"

        response = request(:get, path)
        normalize_pull_request(response)
      end

      def list_pull_requests(repo:, state: "open", head: nil, base: nil)
        path = "#{API_VERSION}/repos/#{repo}/pulls"

        params = { state: state }
        params[:head] = head if head
        params[:base] = base if base

        response = request(:get, path, params: params)
        response.map { |pr| normalize_pull_request(pr) }
      end

      def merge_pull_request(repo:, number:, merge_method: "merge", commit_message: nil)
        path = "#{API_VERSION}/repos/#{repo}/pulls/#{number}/merge"

        body = {
          Do: map_merge_method(merge_method)
        }
        body[:MergeTitleField] = commit_message if commit_message

        log_info("Merging pull request", repo: repo, number: number, method: merge_method)
        request(:post, path, body: body)
      end

      # =============================================================================
      # COMMENTS
      # =============================================================================

      def create_issue_comment(repo:, number:, body:)
        path = "#{API_VERSION}/repos/#{repo}/issues/#{number}/comments"

        log_info("Creating comment", repo: repo, number: number)
        response = request(:post, path, body: { body: body })
        normalize_comment(response)
      end

      def update_issue_comment(repo:, comment_id:, body:)
        # Gitea uses issue comments endpoint for both issues and PRs
        # We need the repo to construct the path but comment_id is global
        path = "#{API_VERSION}/repos/#{repo}/issues/comments/#{comment_id}"

        log_info("Updating comment", comment_id: comment_id)
        response = request(:patch, path, body: { body: body })
        normalize_comment(response)
      end

      def list_issue_comments(repo:, number:)
        path = "#{API_VERSION}/repos/#{repo}/issues/#{number}/comments"

        response = request(:get, path)
        response.map { |comment| normalize_comment(comment) }
      end

      # =============================================================================
      # REPOSITORY
      # =============================================================================

      def get_repository(repo:)
        path = "#{API_VERSION}/repos/#{repo}"

        response = request(:get, path)
        normalize_repository(response)
      end

      def list_branches(repo:)
        path = "#{API_VERSION}/repos/#{repo}/branches"

        response = request(:get, path)
        response.map { |branch| normalize_branch(branch) }
      end

      def get_branch(repo:, branch:)
        path = "#{API_VERSION}/repos/#{repo}/branches/#{branch}"

        response = request(:get, path)
        normalize_branch(response)
      end

      # =============================================================================
      # FILES
      # =============================================================================

      def get_file_contents(repo:, path:, ref: nil)
        api_path = "#{API_VERSION}/repos/#{repo}/contents/#{path}"
        params = ref ? { ref: ref } : nil

        response = request(:get, api_path, params: params)

        {
          content: Base64.decode64(response["content"] || ""),
          sha: response["sha"],
          path: response["path"],
          size: response["size"],
          encoding: response["encoding"]
        }
      end

      def create_or_update_file(repo:, path:, content:, message:, branch:, sha: nil)
        api_path = "#{API_VERSION}/repos/#{repo}/contents/#{path}"

        body = {
          content: Base64.strict_encode64(content),
          message: message,
          branch: branch
        }
        body[:sha] = sha if sha

        method = sha ? :put : :post
        log_info("#{sha ? 'Updating' : 'Creating'} file", repo: repo, path: path)
        request(method, api_path, body: body)
      end

      # =============================================================================
      # WEBHOOKS
      # =============================================================================

      def create_webhook(repo:, url:, events:, secret: nil)
        path = "#{API_VERSION}/repos/#{repo}/hooks"

        body = {
          type: "gitea",
          active: true,
          config: {
            url: url,
            content_type: "json"
          },
          events: map_webhook_events(events)
        }
        body[:config][:secret] = secret if secret

        log_info("Creating webhook", repo: repo, url: url)
        request(:post, path, body: body)
      end

      def list_webhooks(repo:)
        path = "#{API_VERSION}/repos/#{repo}/hooks"
        request(:get, path)
      end

      def delete_webhook(repo:, webhook_id:)
        path = "#{API_VERSION}/repos/#{repo}/hooks/#{webhook_id}"

        log_info("Deleting webhook", repo: repo, webhook_id: webhook_id)
        request(:delete, path)
        true
      end

      # =============================================================================
      # USERS
      # =============================================================================

      def get_current_user
        path = "#{API_VERSION}/user"
        response = request(:get, path)

        {
          id: response["id"],
          login: response["login"],
          email: response["email"],
          name: response["full_name"] || response["login"],
          avatar_url: response["avatar_url"]
        }
      end

      # =============================================================================
      # GITEA-SPECIFIC: Actions/Workflows
      # =============================================================================

      def dispatch_workflow(repo:, workflow:, ref:, inputs: {})
        # Gitea Actions uses the same dispatch API as GitHub
        path = "#{API_VERSION}/repos/#{repo}/actions/workflows/#{workflow}/dispatches"

        body = {
          ref: ref,
          inputs: inputs
        }

        log_info("Dispatching workflow", repo: repo, workflow: workflow, ref: ref)
        request(:post, path, body: body)
        { dispatched: true, workflow: workflow, ref: ref }
      rescue NotFoundError
        # Workflow dispatch not available
        nil
      end

      # List workflow runs
      def list_workflow_runs(repo:, workflow: nil, branch: nil, status: nil)
        path = if workflow
                 "#{API_VERSION}/repos/#{repo}/actions/workflows/#{workflow}/runs"
               else
                 "#{API_VERSION}/repos/#{repo}/actions/runs"
               end

        params = {}
        params[:branch] = branch if branch
        params[:status] = status if status

        request(:get, path, params: params)
      end

      # Get workflow run details
      def get_workflow_run(repo:, run_id:)
        path = "#{API_VERSION}/repos/#{repo}/actions/runs/#{run_id}"
        request(:get, path)
      end

      # Get workflow run logs
      def get_workflow_run_logs(repo:, run_id:)
        path = "#{API_VERSION}/repos/#{repo}/actions/runs/#{run_id}/logs"
        request(:get, path)
      end

      protected

      def authorization_header
        "token #{access_token}"
      end

      def map_status(state)
        {
          STATUS_PENDING => "pending",
          STATUS_RUNNING => "pending",
          STATUS_SUCCESS => "success",
          STATUS_FAILURE => "failure",
          STATUS_ERROR => "error",
          STATUS_CANCELLED => "failure"
        }[state] || "pending"
      end

      def normalize_status(state)
        {
          "pending" => STATUS_PENDING,
          "success" => STATUS_SUCCESS,
          "failure" => STATUS_FAILURE,
          "error" => STATUS_ERROR
        }[state] || STATUS_PENDING
      end

      def map_merge_method(method)
        {
          "merge" => "merge",
          "squash" => "squash",
          "rebase" => "rebase-merge"
        }[method] || "merge"
      end

      def map_webhook_events(events)
        # Gitea event names are similar to GitHub
        events.map do |event|
          case event
          when "push" then "push"
          when "pull_request" then "pull_request"
          when "pull_request_review" then "pull_request_review"
          when "issues" then "issues"
          when "issue_comment" then "issue_comment"
          when "create" then "create"
          when "delete" then "delete"
          when "release" then "release"
          else event
          end
        end
      end

      def normalize_commit_status(status)
        {
          id: status["id"],
          state: normalize_status(status["status"]),
          context: status["context"],
          description: status["description"],
          target_url: status["target_url"],
          created_at: status["created_at"],
          updated_at: status["updated_at"]
        }
      end

      def normalize_pull_request(pr)
        {
          id: pr["id"],
          number: pr["number"],
          title: pr["title"],
          body: pr["body"],
          state: pr["state"],
          merged: pr["merged"],
          draft: pr["draft"] || false,
          head: {
            ref: pr.dig("head", "ref"),
            sha: pr.dig("head", "sha"),
            repo: pr.dig("head", "repo", "full_name")
          },
          base: {
            ref: pr.dig("base", "ref"),
            sha: pr.dig("base", "sha"),
            repo: pr.dig("base", "repo", "full_name")
          },
          user: {
            login: pr.dig("user", "login"),
            id: pr.dig("user", "id")
          },
          html_url: pr["html_url"],
          created_at: pr["created_at"],
          updated_at: pr["updated_at"],
          merged_at: pr["merged_at"],
          mergeable: pr["mergeable"]
        }
      end

      def normalize_comment(comment)
        {
          id: comment["id"],
          body: comment["body"],
          user: {
            login: comment.dig("user", "login"),
            id: comment.dig("user", "id")
          },
          html_url: comment["html_url"],
          created_at: comment["created_at"],
          updated_at: comment["updated_at"]
        }
      end

      def normalize_repository(repo)
        {
          id: repo["id"],
          name: repo["name"],
          full_name: repo["full_name"],
          description: repo["description"],
          private: repo["private"],
          fork: repo["fork"],
          default_branch: repo["default_branch"],
          clone_url: repo["clone_url"],
          ssh_url: repo["ssh_url"],
          html_url: repo["html_url"],
          owner: {
            login: repo.dig("owner", "login"),
            id: repo.dig("owner", "id")
          },
          permissions: repo["permissions"]
        }
      end

      def normalize_branch(branch)
        {
          name: branch["name"],
          commit: {
            sha: branch.dig("commit", "id") || branch.dig("commit", "sha"),
            message: branch.dig("commit", "message")
          },
          protected: branch["protected"]
        }
      end
    end
  end
end
