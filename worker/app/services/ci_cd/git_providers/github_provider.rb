# frozen_string_literal: true

require_relative "base_provider"

module CiCd
  module GitProviders
    # GitHub API integration
    # API Documentation: https://docs.github.com/en/rest
    class GithubProvider < BaseProvider
      DEFAULT_API_URL = "https://api.github.com"

      def initialize(api_url: nil, access_token:, logger: nil)
        super(
          api_url: api_url || DEFAULT_API_URL,
          access_token: access_token,
          logger: logger
        )
      end

      def provider_type
        :github
      end

      # =============================================================================
      # COMMIT STATUS
      # =============================================================================

      def create_commit_status(repo:, sha:, state:, context:, description:, target_url: nil)
        path = "/repos/#{repo}/statuses/#{sha}"

        body = {
          state: map_status(state),
          context: context,
          description: description&.slice(0, 140)
        }
        body[:target_url] = target_url if target_url

        log_info("Creating commit status", repo: repo, sha: sha[0..7], state: state)
        response = request(:post, path, body: body)
        normalize_commit_status(response)
      end

      def get_commit_statuses(repo:, sha:)
        path = "/repos/#{repo}/commits/#{sha}/statuses"

        response = request(:get, path)
        response.map { |status| normalize_commit_status(status) }
      end

      # Also get combined status
      def get_combined_status(repo:, sha:)
        path = "/repos/#{repo}/commits/#{sha}/status"
        request(:get, path)
      end

      # =============================================================================
      # PULL REQUESTS
      # =============================================================================

      def create_pull_request(repo:, title:, head:, base:, body: nil, draft: false)
        path = "/repos/#{repo}/pulls"

        request_body = {
          title: title,
          head: head,
          base: base,
          body: body,
          draft: draft
        }

        log_info("Creating pull request", repo: repo, head: head, base: base)
        response = request(:post, path, body: request_body)
        normalize_pull_request(response)
      end

      def get_pull_request(repo:, number:)
        path = "/repos/#{repo}/pulls/#{number}"

        response = request(:get, path)
        normalize_pull_request(response)
      end

      def list_pull_requests(repo:, state: "open", head: nil, base: nil)
        path = "/repos/#{repo}/pulls"

        params = { state: state }
        params[:head] = head if head
        params[:base] = base if base

        response = request(:get, path, params: params)
        response.map { |pr| normalize_pull_request(pr) }
      end

      def merge_pull_request(repo:, number:, merge_method: "merge", commit_message: nil)
        path = "/repos/#{repo}/pulls/#{number}/merge"

        body = {
          merge_method: merge_method
        }
        body[:commit_message] = commit_message if commit_message

        log_info("Merging pull request", repo: repo, number: number, method: merge_method)
        request(:put, path, body: body)
      end

      # =============================================================================
      # COMMENTS
      # =============================================================================

      def create_issue_comment(repo:, number:, body:)
        path = "/repos/#{repo}/issues/#{number}/comments"

        log_info("Creating comment", repo: repo, number: number)
        response = request(:post, path, body: { body: body })
        normalize_comment(response)
      end

      def update_issue_comment(repo:, comment_id:, body:)
        path = "/repos/#{repo}/issues/comments/#{comment_id}"

        log_info("Updating comment", comment_id: comment_id)
        response = request(:patch, path, body: { body: body })
        normalize_comment(response)
      end

      def list_issue_comments(repo:, number:)
        path = "/repos/#{repo}/issues/#{number}/comments"

        response = request(:get, path)
        response.map { |comment| normalize_comment(comment) }
      end

      # PR review comments (different from issue comments)
      def create_review_comment(repo:, number:, body:, commit_id:, path:, line: nil, side: nil)
        api_path = "/repos/#{repo}/pulls/#{number}/comments"

        request_body = {
          body: body,
          commit_id: commit_id,
          path: path
        }
        request_body[:line] = line if line
        request_body[:side] = side if side

        request(:post, api_path, body: request_body)
      end

      # =============================================================================
      # REPOSITORY
      # =============================================================================

      def get_repository(repo:)
        path = "/repos/#{repo}"

        response = request(:get, path)
        normalize_repository(response)
      end

      def list_branches(repo:)
        path = "/repos/#{repo}/branches"

        response = request(:get, path)
        response.map { |branch| normalize_branch(branch) }
      end

      def get_branch(repo:, branch:)
        path = "/repos/#{repo}/branches/#{branch}"

        response = request(:get, path)
        normalize_branch(response)
      end

      # =============================================================================
      # FILES
      # =============================================================================

      def get_file_contents(repo:, path:, ref: nil)
        api_path = "/repos/#{repo}/contents/#{path}"
        params = ref ? { ref: ref } : nil

        response = request(:get, api_path, params: params)

        {
          content: Base64.decode64(response["content"]&.gsub("\n", "") || ""),
          sha: response["sha"],
          path: response["path"],
          size: response["size"],
          encoding: response["encoding"]
        }
      end

      def create_or_update_file(repo:, path:, content:, message:, branch:, sha: nil)
        api_path = "/repos/#{repo}/contents/#{path}"

        body = {
          content: Base64.strict_encode64(content),
          message: message,
          branch: branch
        }
        body[:sha] = sha if sha

        log_info("#{sha ? 'Updating' : 'Creating'} file", repo: repo, path: path)
        request(:put, api_path, body: body)
      end

      # =============================================================================
      # WEBHOOKS
      # =============================================================================

      def create_webhook(repo:, url:, events:, secret: nil)
        path = "/repos/#{repo}/hooks"

        body = {
          name: "web",
          active: true,
          events: events,
          config: {
            url: url,
            content_type: "json"
          }
        }
        body[:config][:secret] = secret if secret

        log_info("Creating webhook", repo: repo, url: url)
        request(:post, path, body: body)
      end

      def list_webhooks(repo:)
        path = "/repos/#{repo}/hooks"
        request(:get, path)
      end

      def delete_webhook(repo:, webhook_id:)
        path = "/repos/#{repo}/hooks/#{webhook_id}"

        log_info("Deleting webhook", repo: repo, webhook_id: webhook_id)
        request(:delete, path)
        true
      end

      # =============================================================================
      # USERS
      # =============================================================================

      def get_current_user
        path = "/user"
        response = request(:get, path)

        {
          id: response["id"],
          login: response["login"],
          email: response["email"],
          name: response["name"],
          avatar_url: response["avatar_url"]
        }
      end

      # =============================================================================
      # GITHUB-SPECIFIC: Actions
      # =============================================================================

      def dispatch_workflow(repo:, workflow:, ref:, inputs: {})
        path = "/repos/#{repo}/actions/workflows/#{workflow}/dispatches"

        body = {
          ref: ref,
          inputs: inputs
        }

        log_info("Dispatching workflow", repo: repo, workflow: workflow, ref: ref)
        request(:post, path, body: body)
        { dispatched: true, workflow: workflow, ref: ref }
      end

      # List workflow runs
      def list_workflow_runs(repo:, workflow: nil, branch: nil, status: nil)
        path = if workflow
                 "/repos/#{repo}/actions/workflows/#{workflow}/runs"
               else
                 "/repos/#{repo}/actions/runs"
               end

        params = {}
        params[:branch] = branch if branch
        params[:status] = status if status

        request(:get, path, params: params)
      end

      # Get workflow run details
      def get_workflow_run(repo:, run_id:)
        path = "/repos/#{repo}/actions/runs/#{run_id}"
        request(:get, path)
      end

      # Download workflow run logs
      def get_workflow_run_logs_url(repo:, run_id:)
        path = "/repos/#{repo}/actions/runs/#{run_id}/logs"
        # This returns a redirect URL for download
        request(:get, path)
      end

      # Re-run a workflow
      def rerun_workflow(repo:, run_id:)
        path = "/repos/#{repo}/actions/runs/#{run_id}/rerun"
        request(:post, path)
      end

      # Cancel a workflow run
      def cancel_workflow_run(repo:, run_id:)
        path = "/repos/#{repo}/actions/runs/#{run_id}/cancel"
        request(:post, path)
      end

      # =============================================================================
      # GITHUB-SPECIFIC: Check Runs (for more detailed status)
      # =============================================================================

      def create_check_run(repo:, name:, head_sha:, status: nil, conclusion: nil, output: nil)
        path = "/repos/#{repo}/check-runs"

        body = {
          name: name,
          head_sha: head_sha
        }
        body[:status] = status if status
        body[:conclusion] = conclusion if conclusion
        body[:output] = output if output

        request(:post, path, body: body)
      end

      def update_check_run(repo:, check_run_id:, status: nil, conclusion: nil, output: nil)
        path = "/repos/#{repo}/check-runs/#{check_run_id}"

        body = {}
        body[:status] = status if status
        body[:conclusion] = conclusion if conclusion
        body[:output] = output if output

        request(:patch, path, body: body)
      end

      protected

      def authorization_header
        "Bearer #{access_token}"
      end

      def apply_headers(request)
        super
        request["X-GitHub-Api-Version"] = "2022-11-28"
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

      def normalize_commit_status(status)
        {
          id: status["id"],
          state: normalize_status(status["state"]),
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
            sha: branch.dig("commit", "sha"),
            message: nil # GitHub doesn't include commit message in branch list
          },
          protected: branch["protected"]
        }
      end
    end
  end
end
