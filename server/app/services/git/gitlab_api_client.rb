# frozen_string_literal: true

module Git
  class GitlabApiClient < ApiClient
    DEFAULT_BASE_URL = "https://gitlab.com/api/v4"

    def initialize(credential)
      super
      @base_url = @provider.api_base_url.presence || DEFAULT_BASE_URL
    end

    # Authentication & User

    def test_connection
      result = get("/user")
      {
        success: true,
        username: result["username"],
        user_id: result["id"].to_s,
        avatar_url: result["avatar_url"],
        email: result["email"],
        scopes: []
      }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def current_user
      get("/user")
    end

    # Repositories (Projects in GitLab)

    def list_repositories(options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 30

      params = {
        page: page,
        per_page: per_page,
        order_by: "updated_at",
        sort: "desc",
        membership: true
      }

      projects = get("/projects", params)
      projects.map { |p| normalize_repository(p) }
    end

    def list_group_repositories(group, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 30

      projects = get("/groups/#{CGI.escape(group)}/projects", page: page, per_page: per_page)
      projects.map { |p| normalize_repository(p) }
    end

    def get_repository(owner, repo)
      project_path = "#{owner}/#{repo}"
      project = get("/projects/#{CGI.escape(project_path)}")
      normalize_repository(project)
    end

    def list_branches(owner, repo, options = {})
      project_path = "#{owner}/#{repo}"
      page = options[:page] || 1
      per_page = options[:per_page] || 30

      branches = get("/projects/#{CGI.escape(project_path)}/repository/branches", page: page, per_page: per_page)
      branches.map { |b| normalize_branch(b) }
    end

    def get_branch(owner, repo, branch)
      project_path = "#{owner}/#{repo}"
      branch_data = get("/projects/#{CGI.escape(project_path)}/repository/branches/#{CGI.escape(branch)}")
      normalize_branch(branch_data)
    end

    def list_commits(owner, repo, options = {})
      project_path = "#{owner}/#{repo}"
      params = {
        page: options[:page] || 1,
        per_page: options[:per_page] || 30
      }
      params[:ref_name] = options[:sha] if options[:sha]
      params[:since] = options[:since].iso8601 if options[:since]
      params[:until] = options[:until].iso8601 if options[:until]

      commits = get("/projects/#{CGI.escape(project_path)}/repository/commits", params)
      commits.map { |c| normalize_commit(c) }
    end

    # Merge Requests (Pull Requests in GitLab)

    def list_pull_requests(owner, repo, options = {})
      project_path = "#{owner}/#{repo}"
      params = {
        state: gitlab_mr_state(options[:state] || "open"),
        page: options[:page] || 1,
        per_page: options[:per_page] || 30,
        order_by: "updated_at",
        sort: "desc"
      }

      mrs = get("/projects/#{CGI.escape(project_path)}/merge_requests", params)
      mrs.map { |mr| normalize_merge_request(mr) }
    end

    def get_pull_request(owner, repo, number)
      project_path = "#{owner}/#{repo}"
      mr = get("/projects/#{CGI.escape(project_path)}/merge_requests/#{number}")
      normalize_merge_request(mr)
    end

    # Issues

    def list_issues(owner, repo, options = {})
      project_path = "#{owner}/#{repo}"
      params = {
        state: gitlab_issue_state(options[:state] || "open"),
        page: options[:page] || 1,
        per_page: options[:per_page] || 30,
        order_by: "updated_at",
        sort: "desc"
      }

      issues = get("/projects/#{CGI.escape(project_path)}/issues", params)
      issues.map { |i| normalize_issue(i) }
    end

    def get_issue(owner, repo, number)
      project_path = "#{owner}/#{repo}"
      issue = get("/projects/#{CGI.escape(project_path)}/issues/#{number}")
      normalize_issue(issue)
    end

    # Webhooks

    def list_webhooks(owner, repo)
      project_path = "#{owner}/#{repo}"
      get("/projects/#{CGI.escape(project_path)}/hooks")
    end

    def create_webhook(repository, secret)
      project_path = "#{repository.owner}/#{repository.name}"

      payload = {
        url: webhook_callback_url,
        push_events: true,
        merge_requests_events: true,
        issues_events: true,
        note_events: true,
        tag_push_events: true,
        pipeline_events: true,
        job_events: true,
        deployment_events: true,
        releases_events: true,
        token: secret,
        enable_ssl_verification: true
      }

      result = post("/projects/#{CGI.escape(project_path)}/hooks", payload)
      { success: true, webhook_id: result["id"].to_s }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_webhook(repository)
      return { success: false, error: "No webhook configured" } unless repository.webhook_id

      project_path = "#{repository.owner}/#{repository.name}"
      delete("/projects/#{CGI.escape(project_path)}/hooks/#{repository.webhook_id}")
      { success: true }
    rescue NotFoundError
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # CI/CD Pipelines

    def list_workflow_runs(owner, repo, options = {})
      project_path = "#{owner}/#{repo}"
      params = {
        page: options[:page] || 1,
        per_page: options[:per_page] || 30,
        order_by: "updated_at",
        sort: "desc"
      }
      params[:status] = options[:status] if options[:status]
      params[:ref] = options[:branch] if options[:branch]

      pipelines = get("/projects/#{CGI.escape(project_path)}/pipelines", params)
      pipelines.map { |p| normalize_pipeline(p) }
    end

    def get_workflow_run(owner, repo, run_id)
      project_path = "#{owner}/#{repo}"
      pipeline = get("/projects/#{CGI.escape(project_path)}/pipelines/#{run_id}")
      normalize_pipeline(pipeline)
    end

    def get_workflow_run_jobs(owner, repo, run_id)
      project_path = "#{owner}/#{repo}"
      jobs = get("/projects/#{CGI.escape(project_path)}/pipelines/#{run_id}/jobs")
      jobs.map { |j| normalize_job(j) }
    end

    def get_job_logs(owner, repo, job_id)
      project_path = "#{owner}/#{repo}"
      get("/projects/#{CGI.escape(project_path)}/jobs/#{job_id}/trace", raw: true)
    end

    def trigger_workflow(owner, repo, _workflow_id, ref, inputs = {})
      project_path = "#{owner}/#{repo}"
      payload = { ref: ref }
      payload[:variables] = inputs.map { |k, v| { key: k.to_s, value: v.to_s } } if inputs.present?

      pipeline = post("/projects/#{CGI.escape(project_path)}/pipeline", payload)
      { success: true, pipeline_id: pipeline["id"] }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def cancel_workflow_run(owner, repo, run_id)
      project_path = "#{owner}/#{repo}"
      post("/projects/#{CGI.escape(project_path)}/pipelines/#{run_id}/cancel")
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def rerun_workflow(owner, repo, run_id)
      project_path = "#{owner}/#{repo}"
      pipeline = post("/projects/#{CGI.escape(project_path)}/pipelines/#{run_id}/retry")
      { success: true, pipeline_id: pipeline["id"] }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Commit Statuses

    def get_commit_statuses(owner, repo, ref)
      project_path = "#{owner}/#{repo}"
      statuses = get("/projects/#{CGI.escape(project_path)}/repository/commits/#{ref}/statuses")
      statuses.map { |s| normalize_commit_status(s) }
    end

    def create_commit_status(owner, repo, sha, state, options = {})
      project_path = "#{owner}/#{repo}"
      payload = { state: gitlab_commit_state(state) }
      payload[:target_url] = options[:target_url] if options[:target_url]
      payload[:description] = options[:description] if options[:description]
      payload[:name] = options[:context] || "default"
      payload[:ref] = options[:ref] if options[:ref]

      result = post("/projects/#{CGI.escape(project_path)}/statuses/#{sha}", payload)
      { success: true, id: result["id"], state: result["status"] }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Branch Protection

    def get_branch_protection(owner, repo, branch)
      project_path = "#{owner}/#{repo}"
      result = get("/projects/#{CGI.escape(project_path)}/protected_branches/#{CGI.escape(branch)}")
      normalize_branch_protection(result)
    rescue NotFoundError
      nil # Branch is not protected
    end

    def update_branch_protection(owner, repo, branch, options = {})
      project_path = "#{owner}/#{repo}"

      # GitLab requires deleting and recreating protection
      begin
        delete("/projects/#{CGI.escape(project_path)}/protected_branches/#{CGI.escape(branch)}")
      rescue NotFoundError
        # Ignore if not protected
      end

      payload = {
        name: branch,
        push_access_level: options[:push_access_level] || 40,      # Maintainers by default
        merge_access_level: options[:merge_access_level] || 40,    # Maintainers by default
        allow_force_push: options[:allow_force_push] || false,
        code_owner_approval_required: options[:code_owner_approval_required] || false
      }

      result = post("/projects/#{CGI.escape(project_path)}/protected_branches", payload)
      { success: true, protection: normalize_branch_protection(result) }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_branch_protection(owner, repo, branch)
      project_path = "#{owner}/#{repo}"
      delete("/projects/#{CGI.escape(project_path)}/protected_branches/#{CGI.escape(branch)}")
      { success: true }
    rescue NotFoundError
      { success: true } # Already unprotected
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def list_protected_branches(owner, repo)
      project_path = "#{owner}/#{repo}"
      result = get("/projects/#{CGI.escape(project_path)}/protected_branches")
      result.map { |branch| normalize_branch_protection(branch) }
    end

    # Deploy Keys

    def list_deploy_keys(owner, repo)
      project_path = "#{owner}/#{repo}"
      result = get("/projects/#{CGI.escape(project_path)}/deploy_keys")
      result.map { |key| normalize_deploy_key(key) }
    end

    def get_deploy_key(owner, repo, key_id)
      project_path = "#{owner}/#{repo}"
      result = get("/projects/#{CGI.escape(project_path)}/deploy_keys/#{key_id}")
      normalize_deploy_key(result)
    end

    def create_deploy_key(owner, repo, title, key, options = {})
      project_path = "#{owner}/#{repo}"
      payload = {
        title: title,
        key: key,
        can_push: options[:read_only] == false
      }

      result = post("/projects/#{CGI.escape(project_path)}/deploy_keys", payload)
      { success: true, key: normalize_deploy_key(result) }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_deploy_key(owner, repo, key_id)
      project_path = "#{owner}/#{repo}"
      delete("/projects/#{CGI.escape(project_path)}/deploy_keys/#{key_id}")
      { success: true }
    rescue NotFoundError
      { success: true } # Already deleted
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Commit Viewing - Comprehensive Git View Capabilities

    def get_commit(owner, repo, sha)
      project_path = "#{owner}/#{repo}"
      commit = get("/projects/#{CGI.escape(project_path)}/repository/commits/#{sha}")
      diff = get("/projects/#{CGI.escape(project_path)}/repository/commits/#{sha}/diff")
      normalize_commit_detail(commit, diff)
    end

    def get_commit_diff(owner, repo, sha)
      project_path = "#{owner}/#{repo}"
      commit = get("/projects/#{CGI.escape(project_path)}/repository/commits/#{sha}")
      diff = get("/projects/#{CGI.escape(project_path)}/repository/commits/#{sha}/diff")
      normalize_gitlab_diff(commit, diff)
    end

    def compare_commits(owner, repo, base, head)
      project_path = "#{owner}/#{repo}"
      result = get("/projects/#{CGI.escape(project_path)}/repository/compare", from: base, to: head)
      normalize_gitlab_comparison(result)
    end

    def get_file_content(owner, repo, path, ref = nil)
      project_path = "#{owner}/#{repo}"
      params = { ref: ref || "HEAD" }
      result = get("/projects/#{CGI.escape(project_path)}/repository/files/#{CGI.escape(path)}", params)
      normalize_gitlab_file_content(result)
    rescue NotFoundError
      nil
    end

    def get_tree(owner, repo, sha, recursive: false)
      project_path = "#{owner}/#{repo}"
      params = { ref: sha, per_page: 100 }
      params[:recursive] = true if recursive
      result = get("/projects/#{CGI.escape(project_path)}/repository/tree", params)
      normalize_gitlab_tree(result, sha)
    end

    def list_tags(owner, repo, options = {})
      project_path = "#{owner}/#{repo}"
      page = options[:page] || 1
      per_page = options[:per_page] || 100

      result = get("/projects/#{CGI.escape(project_path)}/repository/tags", page: page, per_page: per_page)
      result.map { |tag| normalize_gitlab_tag(tag) }
    end

    protected

    def configure_auth(conn)
      # GitLab uses PRIVATE-TOKEN header for personal access tokens
      if @credential.pat?
        conn.headers["PRIVATE-TOKEN"] = @token
      else
        conn.headers["Authorization"] = "Bearer #{@token}"
      end
    end

    private

    def normalize_repository(project)
      {
        "id" => project["id"],
        "name" => project["name"],
        "full_name" => project["path_with_namespace"],
        "description" => project["description"],
        "private" => project["visibility"] == "private",
        "fork" => project["forked_from_project"].present?,
        "archived" => project["archived"],
        "default_branch" => project["default_branch"],
        "clone_url" => project["http_url_to_repo"],
        "ssh_url" => project["ssh_url_to_repo"],
        "html_url" => project["web_url"],
        "stargazers_count" => project["star_count"],
        "forks_count" => project["forks_count"],
        "open_issues_count" => project["open_issues_count"],
        "language" => nil,
        "topics" => project["topics"] || project["tag_list"] || [],
        "updated_at" => project["last_activity_at"],
        "owner" => {
          "login" => project["namespace"]["path"]
        }
      }
    end

    def normalize_branch(branch)
      {
        "name" => branch["name"],
        "commit" => {
          "sha" => branch.dig("commit", "id"),
          "message" => branch.dig("commit", "message")
        },
        "protected" => branch["protected"]
      }
    end

    def normalize_commit(commit)
      {
        "sha" => commit["id"],
        "message" => commit["message"],
        "author" => {
          "login" => commit["author_name"],
          "email" => commit["author_email"]
        },
        "committer" => {
          "login" => commit["committer_name"],
          "email" => commit["committer_email"]
        },
        "created_at" => commit["created_at"]
      }
    end

    def normalize_merge_request(mr)
      {
        "id" => mr["id"],
        "number" => mr["iid"],
        "title" => mr["title"],
        "body" => mr["description"],
        "state" => mr["state"] == "merged" ? "closed" : mr["state"],
        "merged" => mr["state"] == "merged",
        "draft" => mr["draft"] || mr["work_in_progress"],
        "user" => {
          "login" => mr.dig("author", "username"),
          "avatar_url" => mr.dig("author", "avatar_url")
        },
        "head" => {
          "ref" => mr["source_branch"],
          "sha" => mr["sha"]
        },
        "base" => {
          "ref" => mr["target_branch"]
        },
        "html_url" => mr["web_url"],
        "created_at" => mr["created_at"],
        "updated_at" => mr["updated_at"]
      }
    end

    def normalize_issue(issue)
      {
        "id" => issue["id"],
        "number" => issue["iid"],
        "title" => issue["title"],
        "body" => issue["description"],
        "state" => issue["state"] == "opened" ? "open" : "closed",
        "user" => {
          "login" => issue.dig("author", "username"),
          "avatar_url" => issue.dig("author", "avatar_url")
        },
        "labels" => issue["labels"] || [],
        "html_url" => issue["web_url"],
        "created_at" => issue["created_at"],
        "updated_at" => issue["updated_at"]
      }
    end

    def normalize_pipeline(pipeline)
      {
        "id" => pipeline["id"],
        "name" => pipeline["name"] || "Pipeline ##{pipeline['id']}",
        "status" => normalize_pipeline_status(pipeline["status"]),
        "conclusion" => normalize_pipeline_conclusion(pipeline["status"]),
        "run_number" => pipeline["id"],
        "event" => pipeline["source"],
        "head_branch" => pipeline["ref"],
        "head_sha" => pipeline["sha"],
        "html_url" => pipeline["web_url"],
        "created_at" => pipeline["created_at"],
        "updated_at" => pipeline["updated_at"],
        "started_at" => pipeline["started_at"],
        "completed_at" => pipeline["finished_at"],
        "actor" => {
          "login" => pipeline.dig("user", "username")
        }
      }
    end

    def normalize_job(job)
      {
        "id" => job["id"],
        "name" => job["name"],
        "status" => normalize_job_status(job["status"]),
        "conclusion" => normalize_job_conclusion(job["status"]),
        "started_at" => job["started_at"],
        "completed_at" => job["finished_at"],
        "runner" => {
          "name" => job.dig("runner", "name") || job.dig("runner", "description"),
          "id" => job.dig("runner", "id"),
          "os" => nil
        },
        "steps" => (job["artifacts"] || []).map do |a|
          { "name" => a["filename"], "status" => "completed" }
        end
      }
    end

    def normalize_pipeline_status(status)
      case status
      when "created", "waiting_for_resource", "preparing"
        "pending"
      when "pending"
        "queued"
      when "running"
        "in_progress"
      when "success", "failed", "canceled", "skipped"
        "completed"
      else
        status
      end
    end

    def normalize_pipeline_conclusion(status)
      case status
      when "success"
        "success"
      when "failed"
        "failure"
      when "canceled"
        "cancelled"
      when "skipped"
        "skipped"
      else
        nil
      end
    end

    def normalize_job_status(status)
      normalize_pipeline_status(status)
    end

    def normalize_job_conclusion(status)
      normalize_pipeline_conclusion(status)
    end

    def gitlab_mr_state(state)
      case state
      when "open"
        "opened"
      when "closed"
        "closed"
      when "all"
        "all"
      else
        state
      end
    end

    def gitlab_issue_state(state)
      case state
      when "open"
        "opened"
      when "closed"
        "closed"
      when "all"
        "all"
      else
        state
      end
    end

    def gitlab_commit_state(state)
      case state.to_s.downcase
      when "success"
        "success"
      when "pending"
        "pending"
      when "failure", "error"
        "failed"
      when "running"
        "running"
      when "canceled"
        "canceled"
      else
        state
      end
    end

    def normalize_commit_status(status)
      {
        "id" => status["id"],
        "state" => normalize_github_state(status["status"]),
        "context" => status["name"],
        "description" => status["description"],
        "target_url" => status["target_url"],
        "created_at" => status["created_at"],
        "updated_at" => status["finished_at"] || status["created_at"],
        "creator" => {
          "login" => status.dig("author", "username")
        }
      }
    end

    def normalize_github_state(gitlab_state)
      case gitlab_state
      when "success"
        "success"
      when "pending", "running"
        "pending"
      when "failed"
        "failure"
      when "canceled"
        "error"
      else
        gitlab_state
      end
    end

    def normalize_branch_protection(protection)
      {
        "name" => protection["name"],
        "push_access_levels" => protection["push_access_levels"],
        "merge_access_levels" => protection["merge_access_levels"],
        "allow_force_push" => protection["allow_force_push"],
        "code_owner_approval_required" => protection["code_owner_approval_required"],
        # Normalize to GitHub-like structure for consistency
        "required_pull_request_reviews" => protection["merge_access_levels"]&.any?,
        "enforce_admins" => false,
        "required_status_checks" => nil
      }
    end

    def normalize_deploy_key(key)
      {
        id: key["id"],
        title: key["title"],
        key: key["key"],
        fingerprint: key["fingerprint"],
        read_only: !key["can_push"],
        created_at: key["created_at"]
      }
    end

    def normalize_commit_detail(commit, diff_files = [])
      return nil unless commit

      sha = commit["id"]
      parent_ids = commit["parent_ids"] || []
      stats = commit["stats"] || {}

      files = (diff_files || []).map { |f| normalize_gitlab_commit_file(f) }

      {
        sha: sha,
        short_sha: commit["short_id"] || sha[0, 7],
        message: commit["message"] || "",
        title: commit["title"] || (commit["message"] || "").split("\n").first || "",
        body: (commit["message"] || "").split("\n")[1..]&.join("\n")&.strip,
        author: {
          name: commit["author_name"],
          email: commit["author_email"],
          date: commit["authored_date"],
          username: nil,
          avatar_url: nil
        },
        committer: {
          name: commit["committer_name"],
          email: commit["committer_email"],
          date: commit["committed_date"],
          username: nil,
          avatar_url: nil
        },
        authored_date: commit["authored_date"],
        committed_date: commit["committed_date"],
        web_url: commit["web_url"],
        parent_shas: parent_ids,
        is_merge: parent_ids.length > 1,
        is_verified: false,
        verification: nil,
        stats: {
          additions: stats["additions"] || files.sum { |f| f[:additions] },
          deletions: stats["deletions"] || files.sum { |f| f[:deletions] },
          total: stats["total"] || files.sum { |f| f[:changes] },
          files_changed: files.length
        },
        files: files,
        tree_sha: nil
      }
    end

    def normalize_gitlab_commit_file(file)
      return nil unless file

      patch = file["diff"] || ""
      additions = patch.lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
      deletions = patch.lines.count { |l| l.start_with?("-") && !l.start_with?("---") }

      {
        sha: nil,
        filename: file["new_path"] || file["old_path"],
        status: determine_file_status(file),
        additions: additions,
        deletions: deletions,
        changes: additions + deletions,
        patch: patch,
        previous_filename: file["renamed_file"] ? file["old_path"] : nil,
        blob_url: nil,
        raw_url: nil,
        contents_url: nil
      }
    end

    def determine_file_status(file)
      return "added" if file["new_file"]
      return "removed" if file["deleted_file"]
      return "renamed" if file["renamed_file"]
      "modified"
    end

    def normalize_gitlab_diff(commit, diff_files)
      return nil unless commit

      files = (diff_files || []).map { |f| normalize_gitlab_file_diff(f) }
      parent_ids = commit["parent_ids"] || []

      {
        base_sha: parent_ids.first || "",
        head_sha: commit["id"],
        stats: {
          additions: files.sum { |f| f[:additions] },
          deletions: files.sum { |f| f[:deletions] },
          total: files.sum { |f| f[:changes] },
          files_changed: files.length
        },
        files: files
      }
    end

    def normalize_gitlab_file_diff(file)
      return nil unless file

      patch = file["diff"] || ""
      additions = patch.lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
      deletions = patch.lines.count { |l| l.start_with?("-") && !l.start_with?("---") }

      {
        filename: file["new_path"] || file["old_path"],
        status: determine_file_status(file),
        additions: additions,
        deletions: deletions,
        changes: additions + deletions,
        previous_filename: file["renamed_file"] ? file["old_path"] : nil,
        hunks: parse_gitlab_patch_hunks(patch),
        is_binary: file["diff"].blank? && !file["new_file"] && !file["deleted_file"],
        is_large: false,
        truncated: false,
        raw_patch: patch
      }
    end

    def parse_gitlab_patch_hunks(patch)
      return [] if patch.blank?

      hunks = []
      current_hunk = nil
      old_line = 0
      new_line = 0

      patch.lines.each do |line|
        if line.start_with?("@@")
          match = line.match(/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
          if match
            current_hunk = {
              header: line.chomp,
              old_start: match[1].to_i,
              old_lines: match[2]&.to_i || 1,
              new_start: match[3].to_i,
              new_lines: match[4]&.to_i || 1,
              lines: []
            }
            hunks << current_hunk
            old_line = current_hunk[:old_start]
            new_line = current_hunk[:new_start]
          end
        elsif current_hunk
          line_type = case line[0]
                      when "+" then "addition"
                      when "-" then "deletion"
                      when " " then "context"
                      else "context"
                      end

          diff_line = {
            type: line_type,
            content: line[1..].to_s.chomp
          }

          case line_type
          when "deletion"
            diff_line[:old_line_number] = old_line
            old_line += 1
          when "addition"
            diff_line[:new_line_number] = new_line
            new_line += 1
          when "context"
            diff_line[:old_line_number] = old_line
            diff_line[:new_line_number] = new_line
            old_line += 1
            new_line += 1
          end

          current_hunk[:lines] << diff_line
        end
      end

      hunks
    end

    def normalize_gitlab_comparison(comparison)
      return nil unless comparison

      commits = comparison["commits"] || []
      diffs = comparison["diffs"] || []

      files = diffs.map { |f| normalize_gitlab_commit_file(f) }

      {
        url: nil,
        status: commits.any? ? "ahead" : "identical",
        ahead_by: commits.length,
        behind_by: 0,
        total_commits: commits.length,
        base_commit: commits.first ? normalize_commit_detail(commits.first) : nil,
        head_commit: commits.last ? normalize_commit_detail(commits.last) : nil,
        merge_base_commit: nil,
        commits: commits.map { |c| normalize_commit_detail(c) },
        files: files,
        diff_stats: {
          additions: files.sum { |f| f[:additions] },
          deletions: files.sum { |f| f[:deletions] },
          total: files.sum { |f| f[:changes] },
          files_changed: files.length
        }
      }
    end

    def normalize_gitlab_file_content(content)
      return nil unless content

      decoded_content = nil
      if content["encoding"] == "base64" && content["content"]
        decoded_content = Base64.decode64(content["content"]) rescue nil
      end

      is_binary = decoded_content && !decoded_content.valid_encoding?

      {
        name: content["file_name"],
        path: content["file_path"],
        sha: content["blob_id"],
        size: content["size"] || 0,
        type: "file",
        content: is_binary ? nil : decoded_content,
        encoding: is_binary ? "none" : "utf-8",
        download_url: nil,
        web_url: nil,
        is_binary: is_binary,
        lines_count: is_binary ? nil : (decoded_content&.lines&.count || 0)
      }
    end

    def normalize_gitlab_tree(entries, sha)
      return nil unless entries

      {
        sha: sha,
        url: nil,
        entries: entries.map { |entry| normalize_gitlab_tree_entry(entry) },
        truncated: false
      }
    end

    def normalize_gitlab_tree_entry(entry)
      return nil unless entry

      {
        path: entry["path"],
        name: entry["name"],
        type: entry["type"] == "blob" ? "blob" : "tree",
        mode: entry["mode"],
        sha: entry["id"],
        size: nil,
        url: nil
      }
    end

    def normalize_gitlab_tag(tag)
      return nil unless tag

      {
        name: tag["name"],
        sha: tag.dig("commit", "id") || tag["target"],
        message: tag["message"],
        web_url: nil,
        is_release: tag["release"].present?,
        tagger: tag["tagger"] ? {
          name: tag["tagger"]["name"],
          email: tag["tagger"]["email"],
          date: tag["tagger"]["date"]
        } : nil
      }
    end
  end
end
