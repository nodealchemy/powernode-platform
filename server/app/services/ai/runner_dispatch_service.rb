# frozen_string_literal: true

class Ai::RunnerDispatchService
  def initialize(account:, session:)
    @account = account
    @session = session
    @credential = find_credential
    @client = Devops::Git::ApiClient.for(@credential) if @credential
  end

  def select_runner(required_labels: [])
    runners = Devops::GitRunner.where(account: @account).select(&:available?)
    if required_labels.any?
      runners = runners.select { |r| required_labels.all? { |l| r.has_label?(l) } }
    end
    runners.min_by(&:total_jobs_run)
  end

  def dispatch(worktree:, task_input:, runner:)
    repository = resolve_repository
    return { success: false, error: "No repository configured" } unless repository
    return { success: false, error: "No Git provider client available" } unless @client

    workflow_ref = worktree.branch_name
    run_result = @client.trigger_workflow(
      repository.owner, repository.name,
      "agent-execution.yml",
      workflow_ref,
      {
        worktree_id: worktree.id,
        worktree_path: worktree.worktree_path,
        session_id: @session.id,
        task_input: task_input.to_json,
        agent_id: worktree.ai_agent_id,
        runner_labels: runner.labels.join(",")
      }
    )

    dispatch = Ai::RunnerDispatch.create!(
      account: @account,
      worktree_session: @session,
      worktree: worktree,
      git_runner: runner,
      git_repository: repository,
      workflow_run_id: run_result[:run_id]&.to_s,
      workflow_url: build_workflow_url(repository, run_result[:run_id]),
      status: "dispatched",
      input_params: task_input,
      runner_labels: runner.labels,
      dispatched_at: Time.current
    )

    worktree.mark_in_use!
    runner.mark_busy!

    { success: true, dispatch: dispatch }
  rescue StandardError => e
    Rails.logger.error "[RunnerDispatch] Dispatch failed: #{e.message}"
    { success: false, error: e.message }
  end

  def sync_status(dispatch)
    repository = dispatch.git_repository
    return unless repository && @client

    runs = @client.list_workflow_runs(repository.owner, repository.name)
    run = runs&.find { |r| r["id"].to_s == dispatch.workflow_run_id }
    return unless run

    new_status = map_run_status(run["status"], run["conclusion"])
    return if new_status == dispatch.status

    dispatch.update!(status: new_status)

    if %w[completed failed].include?(new_status)
      collect_results(dispatch, repository)
      dispatch.git_runner&.mark_available!
      dispatch.git_runner&.record_job_completion!(success: new_status == "completed")
    end
  rescue StandardError => e
    Rails.logger.error "[RunnerDispatch] Status sync failed: #{e.message}"
  end

  def collect_results(dispatch, repository)
    return unless @client

    jobs = @client.get_workflow_run_jobs(repository.owner, repository.name, dispatch.workflow_run_id) rescue nil
    logs = jobs&.map { |j| @client.get_job_logs(repository.owner, repository.name, j["id"]) rescue nil }&.compact&.join("\n")

    worktree = dispatch.worktree
    manager = Ai::Git::WorktreeManager.new(repository_path: @session.repository_path)
    stats = manager.diff_stats(worktree_path: worktree.worktree_path, base_branch: @session.base_branch) rescue {}

    dispatch.update!(
      logs: logs,
      output_result: { job_count: jobs&.size, stats: stats },
      completed_at: Time.current,
      duration_ms: dispatch.dispatched_at ? ((Time.current - dispatch.dispatched_at) * 1000).to_i : nil
    )

    if dispatch.status == "completed"
      worktree.complete!(head_sha: stats[:head_sha], stats: stats)
    else
      worktree.fail!(error_message: "Runner job failed", error_code: "runner_failure")
    end
  rescue StandardError => e
    Rails.logger.error "[RunnerDispatch] Result collection failed: #{e.message}"
  end

  private

  def find_credential
    @account.git_provider_credentials
            .joins(:provider)
            .where(git_providers: { provider_type: %w[github gitea] })
            .where(is_active: true)
            .order(is_default: :desc, created_at: :desc)
            .first
  end

  def detect_provider_type(credential = @credential)
    credential&.provider&.provider_type
  end

  def dispatch_to_github(task:, runner:, credential:)
    client = Devops::Git::ApiClient.for(credential)
    repository = resolve_repository
    return { success: false, error: "No repository configured" } unless repository

    workflow_ref = @session.base_branch || "main"
    run_result = client.trigger_workflow(
      repository.owner, repository.name,
      "agent-execution.yml",
      workflow_ref,
      {
        session_id: @session.id,
        task_input: task.to_json,
        runner_labels: runner.labels.join(",")
      }
    )

    { success: true, run_result: run_result, repository: repository }
  rescue StandardError => e
    Rails.logger.error "[RunnerDispatch] GitHub dispatch failed: #{e.message}"
    { success: false, error: e.message }
  end

  def resolve_repository
    source = @session.source
    return source.git_repository if source.respond_to?(:git_repository)

    repo_path = @session.repository_path
    return nil if repo_path.blank?

    Devops::GitRepository.where(account: @account)
                         .find_by("full_name LIKE ?", "%#{File.basename(repo_path)}%")
  end

  def map_run_status(status, conclusion)
    case status&.downcase
    when "queued", "waiting" then "dispatched"
    when "in_progress", "running" then "running"
    when "completed"
      case conclusion&.downcase
      when "success" then "completed"
      when "failure", "cancelled" then "failed"
      else "completed"
      end
    else "pending"
    end
  end

  def build_workflow_url(repository, run_id)
    return nil unless repository && run_id

    provider_type = detect_provider_type
    base_url = @credential&.credentials&.dig("url")

    case provider_type
    when "github"
      "#{base_url}/#{repository.full_name}/actions/runs/#{run_id}"
    when "gitea"
      "#{base_url}/#{repository.full_name}/actions/runs/#{run_id}"
    else
      "#{base_url}/#{repository.full_name}/actions/runs/#{run_id}"
    end
  end
end
