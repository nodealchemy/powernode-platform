# frozen_string_literal: true

module Devops
  module Git
  class GithubApiClient < ApiClient
    DEFAULT_BASE_URL = "https://api.github.com"

    def initialize(credential)
      super
      @base_url = @provider.api_base_url.presence || DEFAULT_BASE_URL
    end

    # Authentication & User

    def test_connection
      user = get("/user")
      {
        success: true,
        user: symbolize_keys(user),
        username: user["login"],
        user_id: user["id"].to_s,
        avatar_url: user["avatar_url"],
        email: user["email"],
        scopes: parse_scopes
      }
    end

    def current_user
      symbolize_keys(get("/user"))
    end

    # Repositories

    def list_repositories(options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 100
      sort = options[:sort] || "updated"
      direction = options[:direction] || "desc"

      result = get("/user/repos", page: page, per_page: per_page, sort: sort, direction: direction)
      result.map { |repo| symbolize_keys(repo) }
    end

    def list_org_repositories(org, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 100

      result = get("/orgs/#{org}/repos", page: page, per_page: per_page, sort: "updated")
      result.map { |repo| symbolize_keys(repo) }
    end

    def get_repository(owner, repo)
      symbolize_keys(get("/repos/#{owner}/#{repo}"))
    end

    def list_branches(owner, repo, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 100

      result = get("/repos/#{owner}/#{repo}/branches", page: page, per_page: per_page)
      result.map { |branch| symbolize_keys(branch) }
    end

    def get_branch(owner, repo, branch)
      symbolize_keys(get("/repos/#{owner}/#{repo}/branches/#{branch}"))
    end

    def list_commits(owner, repo, options = {})
      params = {
        page: options[:page] || 1,
        per_page: options[:per_page] || 100
      }
      params[:sha] = options[:sha] if options[:sha]
      params[:since] = options[:since].iso8601 if options[:since]
      params[:until] = options[:until].iso8601 if options[:until]

      result = get("/repos/#{owner}/#{repo}/commits", params)
      result.map { |commit| symbolize_keys(commit) }
    end

    # Pull Requests

    def create_pull_request(owner, repo, title:, body:, head:, base:, draft: false)
      with_error_handling do
        payload = {
          title: title,
          body: body,
          head: head,
          base: base,
          draft: draft
        }
        result = post("/repos/#{owner}/#{repo}/pulls", payload)
        symbolize_keys(result).merge(success: true, pr_number: result["number"], pr_url: result["html_url"])
      end
    end

    def list_pull_requests(owner, repo, options = {})
      params = {
        state: options[:state] || "open",
        page: options[:page] || 1,
        per_page: options[:per_page] || 100,
        sort: options[:sort] || "updated",
        direction: options[:direction] || "desc"
      }

      result = get("/repos/#{owner}/#{repo}/pulls", params)
      result.map { |pr| symbolize_keys(pr) }
    end

    def get_pull_request(owner, repo, number)
      symbolize_keys(get("/repos/#{owner}/#{repo}/pulls/#{number}"))
    end

    # Issues

    def list_issues(owner, repo, options = {})
      params = {
        state: options[:state] || "open",
        page: options[:page] || 1,
        per_page: options[:per_page] || 100,
        sort: options[:sort] || "updated",
        direction: options[:direction] || "desc"
      }

      result = get("/repos/#{owner}/#{repo}/issues", params)
      result.map { |issue| symbolize_keys(issue) }
    end

    def get_issue(owner, repo, number)
      symbolize_keys(get("/repos/#{owner}/#{repo}/issues/#{number}"))
    end

    # Webhooks

    def list_webhooks(owner, repo)
      result = get("/repos/#{owner}/#{repo}/hooks")
      result.map { |hook| symbolize_keys(hook) }
    end

    # Create webhook with explicit parameters (for spec compatibility)
    def create_webhook(owner_or_repo, repo_or_url = nil, webhook_url_or_options = nil, options = {})
      # Support both signatures:
      # 1. create_webhook(owner, repo, webhook_url, options) - new spec-compatible signature
      # 2. create_webhook(repository, secret) - legacy signature for repository objects
      if owner_or_repo.is_a?(String) && repo_or_url.is_a?(String) && webhook_url_or_options.is_a?(String)
        # New signature: owner, repo, webhook_url, options
        owner = owner_or_repo
        repo = repo_or_url
        webhook_url = webhook_url_or_options
        events = options[:events] || webhook_events
        secret = options[:secret]
      elsif owner_or_repo.respond_to?(:owner) && owner_or_repo.respond_to?(:name)
        # Legacy signature: repository object, secret
        repository = owner_or_repo
        secret = repo_or_url
        owner = repository.owner
        repo = repository.name
        webhook_url = webhook_callback_url
        events = webhook_events
      else
        raise ArgumentError, "Invalid arguments for create_webhook"
      end

      payload = {
        name: "web",
        active: true,
        events: events,
        config: {
          url: webhook_url,
          content_type: "json",
          insecure_ssl: "0"
        }
      }
      payload[:config][:secret] = secret if secret.present?

      with_error_handling do
        result = post("/repos/#{owner}/#{repo}/hooks", payload)
        symbolize_keys(result).merge(success: true, webhook_id: result["id"].to_s)
      end
    end

    # Delete webhook with explicit parameters
    def delete_webhook(owner_or_repo, repo_or_nil = nil, webhook_id_or_nil = nil)
      # Support both signatures:
      # 1. delete_webhook(owner, repo, webhook_id) - new spec-compatible signature
      # 2. delete_webhook(repository) - legacy signature
      if owner_or_repo.is_a?(String) && repo_or_nil.is_a?(String) && webhook_id_or_nil.present?
        owner = owner_or_repo
        repo = repo_or_nil
        webhook_id = webhook_id_or_nil
      elsif owner_or_repo.respond_to?(:owner) && owner_or_repo.respond_to?(:name)
        repository = owner_or_repo
        return { success: false, error: "No webhook configured" } unless repository.webhook_id
        owner = repository.owner
        repo = repository.name
        webhook_id = repository.webhook_id
      else
        raise ArgumentError, "Invalid arguments for delete_webhook"
      end

      with_error_handling(default_on_not_found: { success: true }) do
        delete("/repos/#{owner}/#{repo}/hooks/#{webhook_id}")
        { success: true }
      end
    end

    # Webhook Signature Verification
    def verify_webhook_signature(payload, signature, secret)
      return false unless signature.present? && secret.present?

      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      Rack::Utils.secure_compare(expected, signature)
    end

    # GitHub Actions (CI/CD)

    def list_workflow_runs(owner, repo, options = {})
      params = {
        page: options[:page] || 1,
        per_page: options[:per_page] || 100
      }
      params[:status] = options[:status] if options[:status]
      params[:branch] = options[:branch] if options[:branch]
      params[:event] = options[:event] if options[:event]

      result = get("/repos/#{owner}/#{repo}/actions/runs", params)
      {
        total_count: result["total_count"],
        workflow_runs: (result["workflow_runs"] || []).map { |run| symbolize_keys(run) }
      }
    end

    def get_workflow_run(owner, repo, run_id)
      symbolize_keys(get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}"))
    end

    def get_workflow_run_jobs(owner, repo, run_id)
      result = get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/jobs")
      (result["jobs"] || []).map { |job| symbolize_keys(job) }
    end

    # Alias for spec compatibility
    def list_workflow_jobs(owner, repo, run_id)
      result = get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/jobs")
      {
        total_count: result["total_count"],
        jobs: (result["jobs"] || []).map { |job| symbolize_keys(job) }
      }
    end

    def get_job_logs(owner, repo, job_id)
      # GitHub returns a redirect to the logs, we need to follow it
      response = connection.get("/repos/#{owner}/#{repo}/actions/jobs/#{job_id}/logs")

      if response.status == 302
        logs_url = response.headers["location"]
        logs_response = Faraday.get(logs_url)
        logs_response.body
      elsif response.status == 200
        response.body
      else
        handle_response(response, raw: true)
      end
    end

    def list_workflows(owner, repo)
      result = get("/repos/#{owner}/#{repo}/actions/workflows")
      (result["workflows"] || []).map { |workflow| symbolize_keys(workflow) }
    end

    def trigger_workflow(owner, repo, workflow_id, ref, inputs = {})
      with_error_handling do
        payload = { ref: ref }
        payload[:inputs] = inputs if inputs.present?
        post("/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/dispatches", payload)
        { success: true }
      end
    end

    def cancel_workflow_run(owner, repo, run_id)
      with_error_handling do
        post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/cancel")
        { success: true }
      end
    end

    def rerun_workflow(owner, repo, run_id)
      with_error_handling do
        post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun")
        { success: true }
      end
    end

    def rerun_failed_jobs(owner, repo, run_id)
      with_error_handling do
        post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun-failed-jobs")
        { success: true }
      end
    end

    # GitHub Actions Runners (Self-Hosted)

    def list_runners(owner, repo)
      result = get("/repos/#{owner}/#{repo}/actions/runners")
      {
        total_count: result["total_count"],
        runners: (result["runners"] || []).map { |runner| normalize_runner(runner) }
      }
    end

    def list_org_runners(org)
      result = get("/orgs/#{org}/actions/runners")
      {
        total_count: result["total_count"],
        runners: (result["runners"] || []).map { |runner| normalize_runner(runner) }
      }
    end

    def get_runner(owner, repo, runner_id)
      result = get("/repos/#{owner}/#{repo}/actions/runners/#{runner_id}")
      normalize_runner(result)
    end

    def get_org_runner(org, runner_id)
      result = get("/orgs/#{org}/actions/runners/#{runner_id}")
      normalize_runner(result)
    end

    def delete_runner(owner, repo, runner_id)
      with_error_handling(default_on_not_found: { success: true }) do
        delete("/repos/#{owner}/#{repo}/actions/runners/#{runner_id}")
        { success: true }
      end
    end

    def delete_org_runner(org, runner_id)
      with_error_handling(default_on_not_found: { success: true }) do
        delete("/orgs/#{org}/actions/runners/#{runner_id}")
        { success: true }
      end
    end

    def runner_registration_token(owner, repo)
      with_error_handling do
        result = post("/repos/#{owner}/#{repo}/actions/runners/registration-token")
        { token: result["token"], expires_at: result["expires_at"] }
      end
    end

    def org_runner_registration_token(org)
      with_error_handling do
        result = post("/orgs/#{org}/actions/runners/registration-token")
        { token: result["token"], expires_at: result["expires_at"] }
      end
    end

    def runner_removal_token(owner, repo)
      with_error_handling do
        result = post("/repos/#{owner}/#{repo}/actions/runners/remove-token")
        { token: result["token"], expires_at: result["expires_at"] }
      end
    end

    def org_runner_removal_token(org)
      with_error_handling do
        result = post("/orgs/#{org}/actions/runners/remove-token")
        { token: result["token"], expires_at: result["expires_at"] }
      end
    end

    def add_runner_labels(owner, repo, runner_id, labels)
      with_error_handling do
        result = post("/repos/#{owner}/#{repo}/actions/runners/#{runner_id}/labels", { labels: labels })
        { success: true, labels: (result["labels"] || []).map { |l| l["name"] } }
      end
    end

    def remove_runner_label(owner, repo, runner_id, label)
      with_error_handling do
        result = delete("/repos/#{owner}/#{repo}/actions/runners/#{runner_id}/labels/#{label}")
        { success: true, labels: (result["labels"] || []).map { |l| l["name"] } }
      end
    end

    def set_runner_labels(owner, repo, runner_id, labels)
      with_error_handling do
        result = put("/repos/#{owner}/#{repo}/actions/runners/#{runner_id}/labels", { labels: labels })
        { success: true, labels: (result["labels"] || []).map { |l| l["name"] } }
      end
    end

    # Commit Statuses

    def get_commit_statuses(owner, repo, ref)
      result = get("/repos/#{owner}/#{repo}/commits/#{ref}/statuses")
      result.map { |status| symbolize_keys(status) }
    end

    def get_combined_status(owner, repo, ref)
      symbolize_keys(get("/repos/#{owner}/#{repo}/commits/#{ref}/status"))
    end

    def create_commit_status(owner, repo, sha, state, options = {})
      with_error_handling do
        payload = { state: state }
        payload[:target_url] = options[:target_url] if options[:target_url]
        payload[:description] = options[:description] if options[:description]
        payload[:context] = options[:context] || "default"
        result = post("/repos/#{owner}/#{repo}/statuses/#{sha}", payload)
        symbolize_keys(result).merge(success: true)
      end
    end

    # Branch Protection

    def get_branch_protection(owner, repo, branch)
      result = get("/repos/#{owner}/#{repo}/branches/#{branch}/protection")
      symbolize_keys(result)
    rescue NotFoundError
      nil # Branch is not protected
    end

    def update_branch_protection(owner, repo, branch, options = {})
      with_error_handling do
        payload = {
          required_status_checks: options[:required_status_checks],
          enforce_admins: options[:enforce_admins] || false,
          required_pull_request_reviews: options[:required_pull_request_reviews],
          restrictions: options[:restrictions],
          required_linear_history: options[:required_linear_history] || false,
          allow_force_pushes: options[:allow_force_pushes] || false,
          allow_deletions: options[:allow_deletions] || false,
          required_conversation_resolution: options[:required_conversation_resolution] || false
        }.compact
        result = put("/repos/#{owner}/#{repo}/branches/#{branch}/protection", payload)
        { success: true, protection: symbolize_keys(result) }
      end
    end

    def delete_branch_protection(owner, repo, branch)
      with_error_handling(default_on_not_found: { success: true }) do
        delete("/repos/#{owner}/#{repo}/branches/#{branch}/protection")
        { success: true }
      end
    end

    def list_protected_branches(owner, repo)
      result = get("/repos/#{owner}/#{repo}/branches", protected: true)
      result.map { |branch| symbolize_keys(branch) }
    end

    # Deploy Keys

    def list_deploy_keys(owner, repo)
      result = get("/repos/#{owner}/#{repo}/keys")
      result.map { |key| symbolize_keys(key) }
    end

    def get_deploy_key(owner, repo, key_id)
      symbolize_keys(get("/repos/#{owner}/#{repo}/keys/#{key_id}"))
    end

    def create_deploy_key(owner, repo, title, key, options = {})
      with_error_handling do
        payload = { title: title, key: key, read_only: options[:read_only] != false }
        result = post("/repos/#{owner}/#{repo}/keys", payload)
        { success: true, key: symbolize_keys(result) }
      end
    end

    def delete_deploy_key(owner, repo, key_id)
      with_error_handling(default_on_not_found: { success: true }) do
        delete("/repos/#{owner}/#{repo}/keys/#{key_id}")
        { success: true }
      end
    end

    # Rate Limit

    def rate_limit
      symbolize_keys(get("/rate_limit"))
    end

    # Commit Viewing - Comprehensive Git View Capabilities

    def get_commit(owner, repo, sha)
      result = get("/repos/#{owner}/#{repo}/commits/#{sha}")
      normalize_commit_detail(result)
    end

    def get_commit_diff(owner, repo, sha)
      # GitHub returns diff when Accept header is set to diff format
      # But we can get structured data from the commit endpoint
      commit = get("/repos/#{owner}/#{repo}/commits/#{sha}")
      normalize_commit_diff(commit)
    end

    def compare_commits(owner, repo, base, head)
      result = get("/repos/#{owner}/#{repo}/compare/#{base}...#{head}")
      normalize_comparison(result)
    end

    def get_file_content(owner, repo, path, ref = nil)
      params = {}
      params[:ref] = ref if ref
      result = get("/repos/#{owner}/#{repo}/contents/#{path}", params)
      normalize_file_content(result)
    end

    def get_tree(owner, repo, sha, recursive: false)
      params = {}
      params[:recursive] = "1" if recursive
      result = get("/repos/#{owner}/#{repo}/git/trees/#{sha}", params)
      normalize_tree(result)
    end

    def list_tags(owner, repo, options = {})
      page = options[:page] || 1
      per_page = options[:per_page] || 100

      result = get("/repos/#{owner}/#{repo}/tags", page: page, per_page: per_page)
      result.map { |tag| normalize_tag(tag) }
    end

    def get_tag(owner, repo, tag_name)
      # First get the tag ref
      ref = get("/repos/#{owner}/#{repo}/git/refs/tags/#{tag_name}")
      tag_sha = ref["object"]["sha"]

      # If it's an annotated tag, get the tag object
      if ref["object"]["type"] == "tag"
        tag_obj = get("/repos/#{owner}/#{repo}/git/tags/#{tag_sha}")
        normalize_annotated_tag(tag_obj, tag_name)
      else
        # Lightweight tag - points directly to commit
        { name: tag_name, sha: tag_sha, type: "lightweight" }
      end
    rescue NotFoundError
      nil
    end

    # Get raw diff patch for a commit
    def get_commit_patch(owner, repo, sha)
      # GitHub API supports getting raw patch via Accept header
      response = connection.get("/repos/#{owner}/#{repo}/commits/#{sha}") do |req|
        req.headers["Accept"] = "application/vnd.github.patch"
      end

      if response.status == 200
        response.body
      else
        handle_response(response)
      end
    end

    protected

    def configure_auth(conn)
      # GitHub prefers "token" for PATs
      conn.headers["Authorization"] = "token #{@token}"
    end

    def configure_headers(conn)
      super
      conn.headers["Accept"] = "application/vnd.github+json"
      conn.headers["X-GitHub-Api-Version"] = "2022-11-28"
    end

    private

    def webhook_events
      %w[push pull_request pull_request_review issues issue_comment create delete release workflow_run deployment]
    end

    def parse_scopes
      # GitHub returns scopes in the X-OAuth-Scopes header
      # We'd need to make a request to get them, but for test_connection
      # we can just return an empty array and let the user check their scopes
      []
    end

    def normalize_runner(runner)
      return nil unless runner

      {
        id: runner["id"].to_s,
        name: runner["name"],
        status: runner["status"],
        busy: runner["busy"] || false,
        os: runner["os"],
        labels: (runner["labels"] || []).map { |l| l.is_a?(Hash) ? l["name"] : l },
        architecture: nil, # GitHub doesn't provide this directly
        version: nil # GitHub doesn't provide this directly
      }
    end

    def normalize_commit_detail(commit)
      return nil unless commit

      sha = commit["sha"]
      commit_data = commit["commit"] || {}
      author = commit_data["author"] || {}
      committer = commit_data["committer"] || {}
      github_author = commit["author"] || {}
      github_committer = commit["committer"] || {}
      stats = commit["stats"] || {}
      files = commit["files"] || []
      parents = commit["parents"] || []

      {
        sha: sha,
        short_sha: sha[0, 7],
        message: commit_data["message"] || "",
        title: (commit_data["message"] || "").split("\n").first || "",
        body: (commit_data["message"] || "").split("\n")[1..]&.join("\n")&.strip,
        author: {
          name: author["name"],
          email: author["email"],
          date: author["date"],
          username: github_author["login"],
          avatar_url: github_author["avatar_url"]
        },
        committer: {
          name: committer["name"],
          email: committer["email"],
          date: committer["date"],
          username: github_committer["login"],
          avatar_url: github_committer["avatar_url"]
        },
        authored_date: author["date"],
        committed_date: committer["date"],
        web_url: commit["html_url"],
        parent_shas: parents.map { |p| p["sha"] },
        is_merge: parents.length > 1,
        is_verified: commit_data.dig("verification", "verified") || false,
        verification: commit_data["verification"] ? {
          verified: commit_data["verification"]["verified"],
          reason: commit_data["verification"]["reason"],
          signature: commit_data["verification"]["signature"],
          payload: commit_data["verification"]["payload"]
        } : nil,
        stats: {
          additions: stats["additions"] || 0,
          deletions: stats["deletions"] || 0,
          total: stats["total"] || 0,
          files_changed: files.length
        },
        files: files.map { |f| normalize_commit_file(f) },
        tree_sha: commit_data.dig("tree", "sha")
      }
    end

    def normalize_commit_file(file)
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
        blob_url: file["blob_url"],
        raw_url: file["raw_url"],
        contents_url: file["contents_url"]
      }
    end

    def normalize_commit_diff(commit)
      return nil unless commit

      files = commit["files"] || []
      stats = commit["stats"] || {}
      parents = commit["parents"] || []
      base_sha = parents.first&.dig("sha") || ""

      {
        base_sha: base_sha,
        head_sha: commit["sha"],
        stats: {
          additions: stats["additions"] || 0,
          deletions: stats["deletions"] || 0,
          total: stats["total"] || 0,
          files_changed: files.length
        },
        files: files.map { |f| normalize_file_diff(f) }
      }
    end

    def normalize_file_diff(file)
      return nil unless file

      patch = file["patch"] || ""

      {
        filename: file["filename"],
        status: file["status"],
        additions: file["additions"] || 0,
        deletions: file["deletions"] || 0,
        changes: file["changes"] || 0,
        previous_filename: file["previous_filename"],
        hunks: parse_patch_hunks(patch),
        is_binary: file["patch"].nil? && file["changes"].to_i.zero?,
        is_large: file["patch"].nil? && file["changes"].to_i.positive?,
        truncated: false,
        raw_patch: patch
      }
    end

    # parse_patch_hunks is now inherited from ApiClient base class

    def normalize_comparison(comparison)
      return nil unless comparison

      commits = comparison["commits"] || []
      files = comparison["files"] || []
      base_commit = comparison["base_commit"] || {}
      head_commit = commits.last || comparison["head_commit"] || {}
      merge_base = comparison["merge_base_commit"] || base_commit

      {
        url: comparison["html_url"],
        status: comparison["status"],
        ahead_by: comparison["ahead_by"] || 0,
        behind_by: comparison["behind_by"] || 0,
        total_commits: comparison["total_commits"] || commits.length,
        base_commit: normalize_commit_detail(base_commit),
        head_commit: normalize_commit_detail(head_commit),
        merge_base_commit: normalize_commit_detail(merge_base),
        commits: commits.map { |c| normalize_commit_detail(c) },
        files: files.map { |f| normalize_commit_file(f) },
        diff_stats: {
          additions: files.sum { |f| f["additions"].to_i },
          deletions: files.sum { |f| f["deletions"].to_i },
          total: files.sum { |f| f["changes"].to_i },
          files_changed: files.length
        }
      }
    end

    def normalize_file_content(content)
      return nil unless content

      # Handle directory listing (array response)
      if content.is_a?(Array)
        return {
          type: "dir",
          entries: content.map { |entry| normalize_tree_entry(entry) }
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

    def normalize_tree(tree)
      return nil unless tree

      {
        sha: tree["sha"],
        url: tree["url"],
        entries: (tree["tree"] || []).map { |entry| normalize_tree_entry(entry) },
        truncated: tree["truncated"] || false
      }
    end

    def normalize_tree_entry(entry)
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

    def normalize_tag(tag)
      return nil unless tag

      {
        name: tag["name"],
        sha: tag.dig("commit", "sha") || tag["sha"],
        web_url: nil, # GitHub doesn't return this directly
        is_release: false # Would need separate API call
      }
    end

    def normalize_annotated_tag(tag, name)
      return nil unless tag

      {
        name: name,
        sha: tag["sha"],
        message: tag["message"],
        type: "annotated",
        tagger: tag["tagger"] ? {
          name: tag["tagger"]["name"],
          email: tag["tagger"]["email"],
          date: tag["tagger"]["date"]
        } : nil,
        commit_sha: tag.dig("object", "sha")
      }
    end

    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.transform_keys(&:to_sym).transform_values do |value|
        case value
        when Hash then symbolize_keys(value)
        when Array then value.map { |v| v.is_a?(Hash) ? symbolize_keys(v) : v }
        else value
        end
      end
    end
  end
end
end
