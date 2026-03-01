# frozen_string_literal: true

require_relative "base_provider"

module Devops
  module GitProviders
    # GitLab API integration
    # API Documentation: https://docs.gitlab.com/ee/api/rest/
    class GitlabProvider < BaseProvider
      API_VERSION = "/api/v4"

      def provider_type
        :gitlab
      end

      # =============================================================================
      # COMMIT STATUS
      # =============================================================================

      def create_commit_status(repo:, sha:, state:, context:, description:, target_url: nil)
        # GitLab uses project ID or URL-encoded path
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/statuses/#{sha}"

        body = {
          state: map_status(state),
          name: context,
          description: description&.slice(0, 140)
        }
        body[:target_url] = target_url if target_url

        log_info("Creating commit status", repo: repo, sha: sha[0..7], state: state)
        response = request(:post, path, body: body)
        normalize_commit_status(response)
      end

      def get_commit_statuses(repo:, sha:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/repository/commits/#{sha}/statuses"

        response = request(:get, path)
        response.map { |status| normalize_commit_status(status) }
      end

      # =============================================================================
      # MERGE REQUESTS (GitLab's equivalent to PRs)
      # =============================================================================

      def create_pull_request(repo:, title:, head:, base:, body: nil, draft: false)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/merge_requests"

        request_body = {
          title: draft ? "Draft: #{title}" : title,
          source_branch: head,
          target_branch: base,
          description: body
        }

        log_info("Creating merge request", repo: repo, head: head, base: base)
        response = request(:post, path, body: request_body)
        normalize_merge_request(response)
      end

      def get_pull_request(repo:, number:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/merge_requests/#{number}"

        response = request(:get, path)
        normalize_merge_request(response)
      end

      def list_pull_requests(repo:, state: "open", head: nil, base: nil)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/merge_requests"

        params = { state: map_pr_state(state) }
        params[:source_branch] = head if head
        params[:target_branch] = base if base

        response = request(:get, path, params: params)
        response.map { |mr| normalize_merge_request(mr) }
      end

      def merge_pull_request(repo:, number:, merge_method: "merge", commit_message: nil)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/merge_requests/#{number}/merge"

        body = {}
        body[:squash] = true if merge_method == "squash"
        body[:merge_commit_message] = commit_message if commit_message

        log_info("Merging merge request", repo: repo, number: number, method: merge_method)
        response = request(:put, path, body: body)
        normalize_merge_request(response)
      end

      # =============================================================================
      # COMMENTS (Notes in GitLab)
      # =============================================================================

      def create_issue_comment(repo:, number:, body:)
        encoded_repo = URI.encode_www_form_component(repo)
        # GitLab uses different endpoints for issues vs merge requests
        # Try merge request first, fall back to issue
        path = "#{API_VERSION}/projects/#{encoded_repo}/merge_requests/#{number}/notes"

        log_info("Creating note", repo: repo, number: number)
        response = request(:post, path, body: { body: body })
        normalize_note(response)
      rescue NotFoundError
        # Try issue endpoint
        path = "#{API_VERSION}/projects/#{encoded_repo}/issues/#{number}/notes"
        response = request(:post, path, body: { body: body })
        normalize_note(response)
      end

      def update_issue_comment(repo:, comment_id:, body:)
        # GitLab note updates require the noteable type and ID
        # This is a limitation - we'd need to store this context
        log_error("GitLab note updates require additional context (MR/issue ID)")
        raise NotImplementedError, "GitLab note updates require noteable context"
      end

      def list_issue_comments(repo:, number:)
        encoded_repo = URI.encode_www_form_component(repo)
        # Try merge request first
        path = "#{API_VERSION}/projects/#{encoded_repo}/merge_requests/#{number}/notes"

        response = request(:get, path)
        response.map { |note| normalize_note(note) }
      rescue NotFoundError
        path = "#{API_VERSION}/projects/#{encoded_repo}/issues/#{number}/notes"
        response = request(:get, path)
        response.map { |note| normalize_note(note) }
      end

      # =============================================================================
      # REPOSITORY
      # =============================================================================

      def get_repository(repo:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}"

        response = request(:get, path)
        normalize_project(response)
      end

      def list_branches(repo:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/repository/branches"

        response = request(:get, path)
        response.map { |branch| normalize_branch(branch) }
      end

      def get_branch(repo:, branch:)
        encoded_repo = URI.encode_www_form_component(repo)
        encoded_branch = URI.encode_www_form_component(branch)
        path = "#{API_VERSION}/projects/#{encoded_repo}/repository/branches/#{encoded_branch}"

        response = request(:get, path)
        normalize_branch(response)
      end

      # =============================================================================
      # FILES
      # =============================================================================

      def get_file_contents(repo:, path:, ref: nil)
        encoded_repo = URI.encode_www_form_component(repo)
        encoded_path = URI.encode_www_form_component(path)
        api_path = "#{API_VERSION}/projects/#{encoded_repo}/repository/files/#{encoded_path}"

        params = { ref: ref || "HEAD" }
        response = request(:get, api_path, params: params)

        {
          content: Base64.decode64(response["content"] || ""),
          sha: response["blob_id"],
          path: response["file_path"],
          size: response["size"],
          encoding: response["encoding"]
        }
      end

      def create_or_update_file(repo:, path:, content:, message:, branch:, sha: nil)
        encoded_repo = URI.encode_www_form_component(repo)
        encoded_path = URI.encode_www_form_component(path)
        api_path = "#{API_VERSION}/projects/#{encoded_repo}/repository/files/#{encoded_path}"

        body = {
          content: content,
          commit_message: message,
          branch: branch
        }

        method = sha ? :put : :post
        log_info("#{sha ? 'Updating' : 'Creating'} file", repo: repo, path: path)
        request(method, api_path, body: body)
      end

      # =============================================================================
      # WEBHOOKS
      # =============================================================================

      def create_webhook(repo:, url:, events:, secret: nil)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/hooks"

        body = {
          url: url,
          enable_ssl_verification: true
        }
        body[:token] = secret if secret

        # GitLab uses individual boolean flags for events
        events.each do |event|
          case event
          when "push" then body[:push_events] = true
          when "pull_request", "merge_request" then body[:merge_requests_events] = true
          when "issues" then body[:issues_events] = true
          when "issue_comment", "note" then body[:note_events] = true
          when "release" then body[:releases_events] = true
          when "pipeline" then body[:pipeline_events] = true
          when "job" then body[:job_events] = true
          end
        end

        log_info("Creating webhook", repo: repo, url: url)
        request(:post, path, body: body)
      end

      def list_webhooks(repo:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/hooks"
        request(:get, path)
      end

      def delete_webhook(repo:, webhook_id:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/hooks/#{webhook_id}"

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
          login: response["username"],
          email: response["email"],
          name: response["name"],
          avatar_url: response["avatar_url"]
        }
      end

      # =============================================================================
      # GITLAB-SPECIFIC: Pipeline triggers
      # =============================================================================

      def dispatch_workflow(repo:, workflow:, ref:, inputs: {})
        encoded_repo = URI.encode_www_form_component(repo)
        # GitLab uses pipeline triggers with tokens
        # workflow parameter is the trigger token
        path = "#{API_VERSION}/projects/#{encoded_repo}/trigger/pipeline"

        body = {
          ref: ref,
          token: workflow, # In GitLab, this is the trigger token
          variables: inputs.transform_keys { |k| "#{k}" }
        }

        log_info("Triggering pipeline", repo: repo, ref: ref)
        request(:post, path, body: body)
      rescue StandardError => e
        log_error("Pipeline trigger failed", error: e.message)
        nil
      end

      # List pipelines
      def list_pipelines(repo:, ref: nil, status: nil)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/pipelines"

        params = {}
        params[:ref] = ref if ref
        params[:status] = status if status

        request(:get, path, params: params)
      end

      # Get pipeline details
      def get_pipeline(repo:, pipeline_id:)
        encoded_repo = URI.encode_www_form_component(repo)
        path = "#{API_VERSION}/projects/#{encoded_repo}/pipelines/#{pipeline_id}"
        request(:get, path)
      end

      protected

      def authorization_header
        "Bearer #{access_token}"
      end

      def apply_headers(request)
        super
        request["PRIVATE-TOKEN"] = access_token
      end

      def map_status(state)
        {
          STATUS_PENDING => "pending",
          STATUS_RUNNING => "running",
          STATUS_SUCCESS => "success",
          STATUS_FAILURE => "failed",
          STATUS_ERROR => "failed",
          STATUS_CANCELLED => "canceled"
        }[state] || "pending"
      end

      def normalize_status(state)
        {
          "pending" => STATUS_PENDING,
          "running" => STATUS_RUNNING,
          "success" => STATUS_SUCCESS,
          "failed" => STATUS_FAILURE,
          "canceled" => STATUS_CANCELLED
        }[state] || STATUS_PENDING
      end

      def map_pr_state(state)
        {
          "open" => "opened",
          "closed" => "closed",
          "merged" => "merged",
          "all" => "all"
        }[state] || "opened"
      end

      def normalize_commit_status(status)
        {
          id: status["id"],
          state: normalize_status(status["status"]),
          context: status["name"],
          description: status["description"],
          target_url: status["target_url"],
          created_at: status["created_at"],
          updated_at: status["finished_at"]
        }
      end

      def normalize_merge_request(mr)
        {
          id: mr["id"],
          number: mr["iid"], # GitLab uses iid for project-scoped ID
          title: mr["title"]&.sub(/^Draft:\s*/i, ""),
          body: mr["description"],
          state: mr["state"] == "opened" ? "open" : mr["state"],
          merged: mr["state"] == "merged",
          draft: mr["draft"] || mr["title"]&.start_with?("Draft:"),
          head: {
            ref: mr["source_branch"],
            sha: mr["sha"],
            repo: mr.dig("source_project", "path_with_namespace")
          },
          base: {
            ref: mr["target_branch"],
            sha: nil, # GitLab doesn't include this directly
            repo: mr.dig("target_project", "path_with_namespace")
          },
          user: {
            login: mr.dig("author", "username"),
            id: mr.dig("author", "id")
          },
          html_url: mr["web_url"],
          created_at: mr["created_at"],
          updated_at: mr["updated_at"],
          merged_at: mr["merged_at"],
          mergeable: mr["merge_status"] == "can_be_merged"
        }
      end

      def normalize_note(note)
        {
          id: note["id"],
          body: note["body"],
          user: {
            login: note.dig("author", "username"),
            id: note.dig("author", "id")
          },
          html_url: nil, # GitLab doesn't provide direct note URLs
          created_at: note["created_at"],
          updated_at: note["updated_at"]
        }
      end

      def normalize_project(project)
        {
          id: project["id"],
          name: project["name"],
          full_name: project["path_with_namespace"],
          description: project["description"],
          private: project["visibility"] == "private",
          fork: project["forked_from_project"].present?,
          default_branch: project["default_branch"],
          clone_url: project["http_url_to_repo"],
          ssh_url: project["ssh_url_to_repo"],
          html_url: project["web_url"],
          owner: {
            login: project.dig("namespace", "path"),
            id: project.dig("namespace", "id")
          },
          permissions: project["permissions"]
        }
      end

      def normalize_branch(branch)
        {
          name: branch["name"],
          commit: {
            sha: branch.dig("commit", "id"),
            message: branch.dig("commit", "message")
          },
          protected: branch["protected"]
        }
      end
    end
  end
end
