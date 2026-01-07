# frozen_string_literal: true

module Git
  class GiteaApiClient < ApiClient
    # Gitea requires a configured base URL (self-hosted)

    def initialize(credential)
      super
      raise ArgumentError, "Gitea requires a configured API base URL" if @base_url.blank?
    end

    # Authentication & User

    def test_connection
      result = get("/user")
      {
        success: true,
        username: result["login"] || result["username"],
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

    # Repositories

    def list_repositories(options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 30

      repos = get("/user/repos", page: page, limit: per_page)
      repos.map { |r| normalize_repository(r) }
    end

    def list_org_repositories(org, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 30

      repos = get("/orgs/#{org}/repos", page: page, limit: per_page)
      repos.map { |r| normalize_repository(r) }
    end

    def get_repository(owner, repo)
      result = get("/repos/#{owner}/#{repo}")
      normalize_repository(result)
    end

    def list_branches(owner, repo, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 30

      get("/repos/#{owner}/#{repo}/branches", page: page, limit: per_page)
    end

    def get_branch(owner, repo, branch)
      get("/repos/#{owner}/#{repo}/branches/#{branch}")
    end

    def list_commits(owner, repo, options = {})
      params = {
        page: options[:page] || 1,
        limit: options[:per_page] || 30
      }
      params[:sha] = options[:sha] if options[:sha]

      get("/repos/#{owner}/#{repo}/commits", params)
    end

    # Pull Requests

    def list_pull_requests(owner, repo, options = {})
      params = {
        state: options[:state] || "open",
        page: options[:page] || 1,
        limit: options[:per_page] || 30
      }

      get("/repos/#{owner}/#{repo}/pulls", params)
    end

    def get_pull_request(owner, repo, number)
      get("/repos/#{owner}/#{repo}/pulls/#{number}")
    end

    # Issues

    def list_issues(owner, repo, options = {})
      params = {
        state: options[:state] || "open",
        page: options[:page] || 1,
        limit: options[:per_page] || 30
      }

      get("/repos/#{owner}/#{repo}/issues", params)
    end

    def get_issue(owner, repo, number)
      get("/repos/#{owner}/#{repo}/issues/#{number}")
    end

    # Webhooks

    def list_webhooks(owner, repo)
      get("/repos/#{owner}/#{repo}/hooks")
    end

    def create_webhook(repository, secret)
      payload = {
        type: "gitea",
        active: true,
        events: webhook_events,
        config: {
          url: webhook_callback_url,
          content_type: "json",
          secret: secret
        }
      }

      result = post("/repos/#{repository.owner}/#{repository.name}/hooks", payload)
      { success: true, webhook_id: result["id"].to_s }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_webhook(repository)
      return { success: false, error: "No webhook configured" } unless repository.webhook_id

      delete("/repos/#{repository.owner}/#{repository.name}/hooks/#{repository.webhook_id}")
      { success: true }
    rescue NotFoundError
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Gitea Actions (Act Runner CI/CD)

    def list_workflow_runs(owner, repo, options = {})
      params = {
        page: options[:page] || 1,
        limit: options[:per_page] || 30
      }

      result = get("/repos/#{owner}/#{repo}/actions/runs", params)
      runs = result["workflow_runs"] || result || []
      runs.map { |r| normalize_workflow_run(r) }
    rescue NotFoundError
      [] # Actions may not be enabled
    end

    def get_workflow_run(owner, repo, run_id)
      result = get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}")
      normalize_workflow_run(result)
    end

    def get_workflow_run_jobs(owner, repo, run_id)
      result = get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/jobs")
      jobs = result["jobs"] || result || []
      jobs.map { |j| normalize_job(j) }
    rescue NotFoundError
      []
    end

    def get_job_logs(owner, repo, job_id)
      get("/repos/#{owner}/#{repo}/actions/jobs/#{job_id}/logs", raw: true)
    rescue NotFoundError
      nil
    end

    def list_workflows(owner, repo)
      result = get("/repos/#{owner}/#{repo}/actions/workflows")
      result["workflows"] || result || []
    rescue NotFoundError
      []
    end

    def trigger_workflow(owner, repo, workflow_file, ref, inputs = {})
      payload = {
        ref: ref,
        inputs: inputs
      }

      post("/repos/#{owner}/#{repo}/actions/workflows/#{workflow_file}/dispatches", payload)
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def cancel_workflow_run(owner, repo, run_id)
      post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/cancel")
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def rerun_workflow(owner, repo, run_id)
      post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun")
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Act Runner Management

    def list_runners(scope = :repo, owner = nil, repo = nil)
      path = case scope
             when :repo
               "/repos/#{owner}/#{repo}/actions/runners"
             when :org
               "/orgs/#{owner}/actions/runners"
             when :admin
               "/admin/actions/runners"
             else
               raise ArgumentError, "Invalid scope: #{scope}"
             end

      result = get(path)
      runners = result["runners"] || result || []
      runners.map { |r| normalize_runner(r) }
    rescue NotFoundError, ApiError
      []
    end

    def get_runner(runner_id)
      result = get("/admin/actions/runners/#{runner_id}")
      normalize_runner(result)
    end

    def runner_registration_token(scope = :repo, owner = nil, repo = nil)
      path = case scope
             when :repo
               "/repos/#{owner}/#{repo}/actions/runners/registration-token"
             when :org
               "/orgs/#{owner}/actions/runners/registration-token"
             when :admin
               "/admin/actions/runners/registration-token"
             else
               raise ArgumentError, "Invalid scope: #{scope}"
             end

      result = post(path)
      {
        token: result["token"],
        expires_at: nil # Gitea doesn't provide expiry
      }
    rescue ApiError => e
      Rails.logger.error "Failed to get runner registration token: #{e.message}"
      { success: false, error: e.message }
    end

    def delete_runner(runner_id)
      delete("/admin/actions/runners/#{runner_id}")
      { success: true }
    rescue NotFoundError
      { success: true } # Already deleted
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def runner_removal_token(scope = :repo, owner = nil, repo = nil)
      # Gitea doesn't have a separate removal token endpoint
      # The registration token can be used for removal as well
      runner_registration_token(scope, owner, repo)
    end

    def update_runner_labels(runner_id, labels)
      # Gitea requires updating the full runner object
      # First get the runner, then update with new labels
      runner = get_runner(runner_id)
      return { success: false, error: "Runner not found" } unless runner

      payload = { labels: labels }
      result = patch("/admin/actions/runners/#{runner_id}", payload)
      {
        success: true,
        labels: (result["labels"] || []).map { |l| l.is_a?(Hash) ? l["name"] : l }
      }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Commit Statuses

    def get_commit_statuses(owner, repo, ref)
      result = get("/repos/#{owner}/#{repo}/statuses/#{ref}")
      (result || []).map { |s| normalize_commit_status(s) }
    rescue NotFoundError
      []
    end

    def get_combined_status(owner, repo, ref)
      get("/repos/#{owner}/#{repo}/commits/#{ref}/status")
    rescue NotFoundError
      { "state" => "pending", "statuses" => [] }
    end

    def create_commit_status(owner, repo, sha, state, options = {})
      payload = {
        state: gitea_commit_state(state),
        target_url: options[:target_url],
        description: options[:description],
        context: options[:context] || "default"
      }.compact

      result = post("/repos/#{owner}/#{repo}/statuses/#{sha}", payload)
      { success: true, id: result["id"], state: result["status"] }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Branch Protection

    def get_branch_protection(owner, repo, branch)
      result = get("/repos/#{owner}/#{repo}/branch_protections/#{branch}")
      normalize_branch_protection(result)
    rescue NotFoundError
      nil # Branch is not protected
    end

    def update_branch_protection(owner, repo, branch, options = {})
      payload = {
        branch_name: branch,
        enable_push: options[:enable_push] != false,
        enable_push_whitelist: options[:enable_push_whitelist] || false,
        push_whitelist_usernames: options[:push_whitelist_usernames] || [],
        push_whitelist_teams: options[:push_whitelist_teams] || [],
        enable_merge_whitelist: options[:enable_merge_whitelist] || false,
        merge_whitelist_usernames: options[:merge_whitelist_usernames] || [],
        merge_whitelist_teams: options[:merge_whitelist_teams] || [],
        enable_status_check: options[:enable_status_check] || false,
        status_check_contexts: options[:status_check_contexts] || [],
        required_approvals: options[:required_approvals] || 0,
        enable_approvals_whitelist: options[:enable_approvals_whitelist] || false,
        approvals_whitelist_usernames: options[:approvals_whitelist_usernames] || [],
        approvals_whitelist_teams: options[:approvals_whitelist_teams] || [],
        block_on_rejected_reviews: options[:block_on_rejected_reviews] || false,
        block_on_outdated_branch: options[:block_on_outdated_branch] || false,
        dismiss_stale_approvals: options[:dismiss_stale_approvals] || false,
        require_signed_commits: options[:require_signed_commits] || false,
        protected_file_patterns: options[:protected_file_patterns] || ""
      }

      # Try to update existing, or create new
      begin
        result = patch("/repos/#{owner}/#{repo}/branch_protections/#{branch}", payload)
      rescue NotFoundError
        result = post("/repos/#{owner}/#{repo}/branch_protections", payload)
      end

      { success: true, protection: normalize_branch_protection(result) }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_branch_protection(owner, repo, branch)
      delete("/repos/#{owner}/#{repo}/branch_protections/#{branch}")
      { success: true }
    rescue NotFoundError
      { success: true } # Already unprotected
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def list_protected_branches(owner, repo)
      result = get("/repos/#{owner}/#{repo}/branch_protections")
      (result || []).map { |branch| normalize_branch_protection(branch) }
    rescue NotFoundError
      []
    end

    # Deploy Keys

    def list_deploy_keys(owner, repo)
      result = get("/repos/#{owner}/#{repo}/keys")
      (result || []).map { |key| normalize_deploy_key(key) }
    end

    def get_deploy_key(owner, repo, key_id)
      result = get("/repos/#{owner}/#{repo}/keys/#{key_id}")
      normalize_deploy_key(result)
    end

    def create_deploy_key(owner, repo, title, key, options = {})
      payload = {
        title: title,
        key: key,
        read_only: options[:read_only] != false
      }

      result = post("/repos/#{owner}/#{repo}/keys", payload)
      { success: true, key: normalize_deploy_key(result) }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_deploy_key(owner, repo, key_id)
      delete("/repos/#{owner}/#{repo}/keys/#{key_id}")
      { success: true }
    rescue NotFoundError
      { success: true } # Already deleted
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Commit Viewing - Comprehensive Git View Capabilities

    def get_commit(owner, repo, sha)
      # Gitea's git/commits endpoint returns everything including files and stats
      commit = get("/repos/#{owner}/#{repo}/git/commits/#{sha}")
      normalize_gitea_commit_detail(commit)
    end

    def get_commit_diff(owner, repo, sha)
      commit = get("/repos/#{owner}/#{repo}/git/commits/#{sha}")
      diff = get("/repos/#{owner}/#{repo}/commits/#{sha}.diff", raw: true) rescue ""
      normalize_gitea_commit_diff(commit, diff)
    end

    def compare_commits(owner, repo, base, head)
      result = get("/repos/#{owner}/#{repo}/compare/#{base}...#{head}")
      normalize_gitea_comparison(result)
    end

    def get_file_content(owner, repo, path, ref = nil)
      params = {}
      params[:ref] = ref if ref
      result = get("/repos/#{owner}/#{repo}/contents/#{path}", params)
      normalize_gitea_file_content(result)
    rescue NotFoundError
      nil
    end

    def get_tree(owner, repo, sha, recursive: false)
      params = {}
      params[:recursive] = true if recursive
      result = get("/repos/#{owner}/#{repo}/git/trees/#{sha}", params)
      normalize_gitea_tree(result)
    end

    def list_tags(owner, repo, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 100

      result = get("/repos/#{owner}/#{repo}/tags", page: page, limit: per_page)
      result.map { |tag| normalize_gitea_tag(tag) }
    end

    protected

    def configure_auth(conn)
      # Gitea supports both Bearer token and token query parameter
      conn.headers["Authorization"] = "token #{@token}"
    end

    private

    def webhook_events
      %w[push pull_request pull_request_review issues issue_comment create delete release workflow_run]
    end

    def normalize_repository(repo)
      {
        "id" => repo["id"],
        "name" => repo["name"],
        "full_name" => repo["full_name"],
        "description" => repo["description"],
        "private" => repo["private"],
        "fork" => repo["fork"],
        "archived" => repo["archived"],
        "default_branch" => repo["default_branch"],
        "clone_url" => repo["clone_url"],
        "ssh_url" => repo["ssh_url"],
        "html_url" => repo["html_url"],
        "stargazers_count" => repo["stars_count"],
        "forks_count" => repo["forks_count"],
        "open_issues_count" => repo["open_issues_count"],
        "language" => repo["language"],
        "topics" => repo["topics"] || [],
        "updated_at" => repo["updated_at"],
        "owner" => {
          "login" => repo.dig("owner", "login") || repo.dig("owner", "username")
        }
      }
    end

    def normalize_workflow_run(run)
      {
        "id" => run["id"],
        "name" => run["name"] || run["display_title"],
        "status" => normalize_status(run["status"]),
        "conclusion" => run["conclusion"],
        "run_number" => run["run_number"],
        "event" => run["event"],
        "head_branch" => run["head_branch"],
        "head_sha" => run["head_sha"],
        "html_url" => run["html_url"],
        "created_at" => run["created_at"],
        "updated_at" => run["updated_at"],
        "started_at" => run["run_started_at"],
        "completed_at" => run["completed_at"],
        "actor" => {
          "login" => run.dig("actor", "login") || run.dig("actor", "username")
        }
      }
    end

    def normalize_job(job)
      {
        "id" => job["id"],
        "name" => job["name"],
        "status" => normalize_status(job["status"]),
        "conclusion" => job["conclusion"],
        "started_at" => job["started_at"],
        "completed_at" => job["completed_at"],
        "runner_name" => job["runner_name"],
        "runner_id" => job["runner_id"]&.to_s,
        "steps" => (job["steps"] || []).map do |step|
          {
            "name" => step["name"],
            "status" => step["status"],
            "conclusion" => step["conclusion"],
            "number" => step["number"],
            "started_at" => step["started_at"],
            "completed_at" => step["completed_at"]
          }
        end
      }
    end

    def normalize_runner(runner)
      {
        "id" => runner["id"],
        "name" => runner["name"],
        "status" => runner["status"] || (runner["busy"] ? "busy" : "online"),
        "busy" => runner["busy"],
        "labels" => (runner["labels"] || []).map { |l| l.is_a?(Hash) ? l["name"] : l },
        "version" => runner["version"],
        "os" => runner["os"],
        "arch" => runner["arch"]
      }
    end

    def normalize_status(status)
      case status&.downcase
      when "queued", "waiting"
        "queued"
      when "pending"
        "pending"
      when "in_progress", "running"
        "in_progress"
      when "completed", "success"
        "completed"
      when "failure", "failed"
        "failed"
      when "cancelled", "canceled"
        "cancelled"
      when "skipped"
        "skipped"
      else
        status || "pending"
      end
    end

    def normalize_commit_status(status)
      {
        "id" => status["id"],
        "state" => status["status"],
        "context" => status["context"],
        "description" => status["description"],
        "target_url" => status["target_url"],
        "created_at" => status["created_at"],
        "updated_at" => status["updated_at"],
        "creator" => {
          "login" => status.dig("creator", "login") || status.dig("creator", "username")
        }
      }
    end

    def gitea_commit_state(state)
      case state.to_s.downcase
      when "success"
        "success"
      when "pending"
        "pending"
      when "failure"
        "failure"
      when "error"
        "error"
      when "warning"
        "warning"
      else
        state
      end
    end

    def normalize_branch_protection(protection)
      {
        "branch_name" => protection["branch_name"],
        "enable_push" => protection["enable_push"],
        "enable_push_whitelist" => protection["enable_push_whitelist"],
        "push_whitelist_usernames" => protection["push_whitelist_usernames"],
        "enable_merge_whitelist" => protection["enable_merge_whitelist"],
        "merge_whitelist_usernames" => protection["merge_whitelist_usernames"],
        "enable_status_check" => protection["enable_status_check"],
        "status_check_contexts" => protection["status_check_contexts"],
        "required_approvals" => protection["required_approvals"],
        "block_on_rejected_reviews" => protection["block_on_rejected_reviews"],
        "dismiss_stale_approvals" => protection["dismiss_stale_approvals"],
        "require_signed_commits" => protection["require_signed_commits"],
        # Normalize to GitHub-like structure for consistency
        "required_pull_request_reviews" => (protection["required_approvals"] || 0) > 0,
        "enforce_admins" => false,
        "required_status_checks" => protection["enable_status_check"] ? {
          "contexts" => protection["status_check_contexts"] || []
        } : nil
      }
    end

    def normalize_deploy_key(key)
      {
        "id" => key["id"],
        "title" => key["title"],
        "key" => key["key"],
        "fingerprint" => key["fingerprint"],
        "read_only" => key["read_only"],
        "created_at" => key["created_at"]
      }
    end

    def normalize_gitea_commit_detail(commit)
      return nil unless commit

      sha = commit["sha"]
      parents = commit["parents"] || []
      # Gitea nests author/committer info inside 'commit' object
      commit_data = commit["commit"] || {}
      author = commit_data["author"] || {}
      committer = commit_data["committer"] || {}
      message = commit_data["message"] || ""
      verification = commit_data["verification"]
      # Stats and files are directly on the response
      stats = commit["stats"] || {}
      files = commit["files"] || []

      {
        sha: sha,
        short_sha: sha[0, 7],
        message: message,
        title: message.split("\n").first || "",
        body: message.split("\n")[1..]&.join("\n")&.strip,
        author: {
          name: author["name"],
          email: author["email"],
          date: author["date"],
          username: commit.dig("author", "login") || commit.dig("author", "username"),
          avatar_url: commit.dig("author", "avatar_url")
        },
        committer: {
          name: committer["name"],
          email: committer["email"],
          date: committer["date"],
          username: commit.dig("committer", "login") || commit.dig("committer", "username"),
          avatar_url: commit.dig("committer", "avatar_url")
        },
        authored_date: author["date"],
        committed_date: committer["date"],
        web_url: commit["html_url"],
        parent_shas: parents.map { |p| p["sha"] },
        is_merge: parents.length > 1,
        is_verified: verification&.dig("verified") || false,
        verification: verification ? {
          verified: verification["verified"],
          reason: verification["reason"],
          signature: verification["signature"],
          payload: verification["payload"]
        } : nil,
        stats: {
          additions: stats["additions"] || 0,
          deletions: stats["deletions"] || 0,
          total: stats["total"] || 0,
          files_changed: files.length
        },
        files: files.map { |f| normalize_gitea_commit_file(f) },
        tree_sha: commit_data.dig("tree", "sha")
      }
    end

    def normalize_gitea_commit_file(file)
      return nil unless file

      {
        sha: file["sha"],
        filename: file["filename"],
        status: file["status"],
        additions: file["additions"] || 0,
        deletions: file["deletions"] || 0,
        changes: file["changes"] || 0,
        patch: file["patch"],
        previous_filename: file["previous_filename"],
        blob_url: nil,
        raw_url: file["raw_url"],
        contents_url: file["contents_url"]
      }
    end

    def normalize_gitea_commit_diff(commit, raw_diff)
      return nil unless commit

      files = parse_raw_diff_to_files(raw_diff)
      parents = commit["parents"] || []
      # Use stats from commit if available, otherwise calculate from parsed diff
      commit_stats = commit["stats"] || {}

      {
        base_sha: parents.first&.dig("sha") || "",
        head_sha: commit["sha"],
        stats: {
          additions: commit_stats["additions"] || files.sum { |f| f[:additions] },
          deletions: commit_stats["deletions"] || files.sum { |f| f[:deletions] },
          total: commit_stats["total"] || files.sum { |f| f[:changes] },
          files_changed: (commit["files"] || files).length
        },
        files: files
      }
    end

    def parse_raw_diff_to_files(raw_diff)
      return [] if raw_diff.blank?

      files = []
      current_file = nil

      raw_diff.lines.each do |line|
        if line.start_with?("diff --git")
          files << current_file if current_file
          match = line.match(%r{diff --git a/(.+) b/(.+)})
          current_file = {
            filename: match ? match[2] : "",
            status: "modified",
            additions: 0,
            deletions: 0,
            changes: 0,
            previous_filename: nil,
            hunks: [],
            is_binary: false,
            is_large: false,
            truncated: false,
            raw_patch: ""
          }
        elsif current_file
          current_file[:raw_patch] += line

          if line.start_with?("new file")
            current_file[:status] = "added"
          elsif line.start_with?("deleted file")
            current_file[:status] = "removed"
          elsif line.start_with?("rename from")
            current_file[:status] = "renamed"
            current_file[:previous_filename] = line.sub("rename from ", "").strip
          elsif line.start_with?("Binary files")
            current_file[:is_binary] = true
          elsif line.start_with?("+") && !line.start_with?("+++")
            current_file[:additions] += 1
            current_file[:changes] += 1
          elsif line.start_with?("-") && !line.start_with?("---")
            current_file[:deletions] += 1
            current_file[:changes] += 1
          end
        end
      end

      files << current_file if current_file

      # Parse hunks for each file
      files.each do |file|
        file[:hunks] = parse_gitea_patch_hunks(file[:raw_patch])
      end

      files
    end

    def parse_gitea_patch_hunks(patch)
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
        elsif current_hunk && !line.start_with?("diff --git", "---", "+++", "index ", "new file", "deleted file", "rename")
          line_type = case line[0]
                      when "+" then "addition"
                      when "-" then "deletion"
                      when " " then "context"
                      else next # Skip other lines
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

    def normalize_gitea_comparison(comparison)
      return nil unless comparison

      commits = comparison["commits"] || []
      files = []

      {
        url: comparison["html_url"],
        status: commits.any? ? "ahead" : "identical",
        ahead_by: commits.length,
        behind_by: 0,
        total_commits: commits.length,
        base_commit: commits.first ? normalize_gitea_commit_detail(commits.first) : nil,
        head_commit: commits.last ? normalize_gitea_commit_detail(commits.last) : nil,
        merge_base_commit: nil,
        commits: commits.map { |c| normalize_gitea_commit_detail(c) },
        files: files,
        diff_stats: {
          additions: files.sum { |f| f[:additions] },
          deletions: files.sum { |f| f[:deletions] },
          total: files.sum { |f| f[:changes] },
          files_changed: files.length
        }
      }
    end

    def normalize_gitea_file_content(content)
      return nil unless content

      # Handle directory listing (array response)
      if content.is_a?(Array)
        return {
          type: "dir",
          entries: content.map { |entry| normalize_gitea_tree_entry(entry) }
        }
      end

      decoded_content = nil
      if content["encoding"] == "base64" && content["content"]
        decoded_content = Base64.decode64(content["content"]) rescue nil
      end

      is_binary = decoded_content && !decoded_content.valid_encoding?

      {
        name: content["name"],
        path: content["path"],
        sha: content["sha"],
        size: content["size"] || 0,
        type: content["type"],
        content: is_binary ? nil : decoded_content,
        encoding: is_binary ? "none" : "utf-8",
        download_url: content["download_url"],
        web_url: content["html_url"],
        is_binary: is_binary,
        lines_count: is_binary ? nil : (decoded_content&.lines&.count || 0)
      }
    end

    def normalize_gitea_tree(tree)
      return nil unless tree

      {
        sha: tree["sha"],
        url: tree["url"],
        entries: (tree["tree"] || []).map { |entry| normalize_gitea_tree_entry(entry) },
        truncated: tree["truncated"] || false
      }
    end

    def normalize_gitea_tree_entry(entry)
      return nil unless entry

      {
        path: entry["path"],
        name: entry["path"]&.split("/")&.last || entry["name"],
        type: entry["type"] == "blob" ? "blob" : (entry["type"] == "tree" ? "tree" : entry["type"]),
        mode: entry["mode"],
        sha: entry["sha"],
        size: entry["size"],
        url: entry["url"]
      }
    end

    def normalize_gitea_tag(tag)
      return nil unless tag

      {
        name: tag["name"],
        sha: tag.dig("commit", "sha") || tag["id"],
        message: tag["message"],
        web_url: nil,
        is_release: false
      }
    end
  end
end
