# frozen_string_literal: true

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

      result = post("/repos/#{owner}/#{repo}/hooks", payload)
      symbolize_keys(result).merge(success: true, webhook_id: result["id"].to_s)
    rescue ApiError => e
      { success: false, error: e.message }
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

      delete("/repos/#{owner}/#{repo}/hooks/#{webhook_id}")
      { success: true }
    rescue NotFoundError
      { success: true } # Already deleted
    rescue ApiError => e
      { success: false, error: e.message }
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
      payload = { ref: ref }
      payload[:inputs] = inputs if inputs.present?

      post("/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/dispatches", payload)
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

    def rerun_failed_jobs(owner, repo, run_id)
      post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun-failed-jobs")
      { success: true }
    rescue ApiError => e
      { success: false, error: e.message }
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
      payload = { state: state }
      payload[:target_url] = options[:target_url] if options[:target_url]
      payload[:description] = options[:description] if options[:description]
      payload[:context] = options[:context] || "default"

      result = post("/repos/#{owner}/#{repo}/statuses/#{sha}", payload)
      symbolize_keys(result).merge(success: true)
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Branch Protection

    def get_branch_protection(owner, repo, branch)
      result = get("/repos/#{owner}/#{repo}/branches/#{branch}/protection")
      symbolize_keys(result)
    rescue NotFoundError
      nil # Branch is not protected
    end

    def update_branch_protection(owner, repo, branch, options = {})
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
    rescue ApiError => e
      { success: false, error: e.message }
    end

    def delete_branch_protection(owner, repo, branch)
      delete("/repos/#{owner}/#{repo}/branches/#{branch}/protection")
      { success: true }
    rescue NotFoundError
      { success: true } # Already unprotected
    rescue ApiError => e
      { success: false, error: e.message }
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
      payload = {
        title: title,
        key: key,
        read_only: options[:read_only] != false
      }

      result = post("/repos/#{owner}/#{repo}/keys", payload)
      { success: true, key: symbolize_keys(result) }
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

    # Rate Limit

    def rate_limit
      symbolize_keys(get("/rate_limit"))
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
