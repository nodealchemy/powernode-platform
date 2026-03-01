# frozen_string_literal: true

class Ai::ExecutionResourceDetailService
  def initialize(account:)
    @account = account
  end

  def fetch(resource_type, id)
    case resource_type
    when "artifact"          then serialize_artifact(id)
    when "git_branch"        then serialize_git_branch(id)
    when "git_merge"         then serialize_git_merge(id)
    when "execution_output"  then serialize_execution_output(id)
    when "shared_memory"     then serialize_shared_memory(id)
    when "trajectory"        then serialize_trajectory(id)
    when "review"            then serialize_review(id)
    when "runner_job"        then serialize_runner_job(id)
    end
  end

  private

  def serialize_artifact(id)
    task = Ai::A2aTask.where(account: @account).find(id)

    {
      resource_type: "artifact",
      source_id: task.id,
      source_type: "Ai::A2aTask",
      source_label: "A2A Task #{task.task_id}",
      name: task.artifacts&.dig(0, "name") || "Unnamed artifact",
      description: task.artifacts&.dig(0, "parts", 0, "text")&.truncate(200),
      status: task.status,
      created_at: task.created_at,
      mime_type: task.artifacts&.dig(0, "mime_type"),

      # Rich fields
      input: task.input,
      output: task.output,
      history: task.history,
      full_artifacts: task.artifacts,
      cost: task.cost,
      tokens_used: task.tokens_used,
      duration_ms: task.duration_ms,
      error_message: task.error_message,
      error_code: task.error_code,
      error_details: task.error_details,
      started_at: task.started_at,
      completed_at: task.completed_at,
      from_agent_name: task.from_agent&.name,
      to_agent_name: task.to_agent&.name,
      subtasks_count: task.subtasks.count,
      retry_count: task.retry_count,
      max_retries: task.max_retries,
      sequence_number: task.sequence_number,
      is_external: task.is_external,
      metadata: task.metadata
    }
  end

  def serialize_git_branch(id)
    wt = Ai::Worktree.joins(:worktree_session)
                      .where(ai_worktree_sessions: { account_id: @account.id })
                      .find(id)

    {
      resource_type: "git_branch",
      source_id: wt.id,
      source_type: "Ai::Worktree",
      source_label: "Worktree Session",
      name: wt.branch_name,
      description: "Worktree branch for #{wt.agent_name || 'agent'}",
      status: wt.status,
      created_at: wt.created_at,

      # Base fields
      branch_name: wt.branch_name,
      commit_sha: wt.head_commit_sha,
      files_changed: wt.files_changed,
      lines_added: wt.lines_added,
      lines_removed: wt.lines_removed,
      agent_name: wt.agent_name,

      # Rich fields
      base_commit_sha: wt.base_commit_sha,
      commit_count: wt.commit_count,
      test_status: (wt.respond_to?(:test_status) ? wt.test_status : nil),
      disk_usage_bytes: wt.disk_usage_bytes,
      tokens_used: (wt.respond_to?(:tokens_used) ? wt.tokens_used : nil),
      estimated_cost_cents: (wt.respond_to?(:estimated_cost_cents) ? wt.estimated_cost_cents : nil),
      healthy: wt.healthy,
      health_message: wt.health_message,
      locked: wt.locked,
      lock_reason: wt.lock_reason,
      worktree_path: wt.worktree_path,
      ready_at: wt.ready_at,
      completed_at: wt.completed_at,
      duration_ms: wt.duration_ms,
      timeout_at: (wt.respond_to?(:timeout_at) ? wt.timeout_at : nil),
      error_message: wt.error_message,
      error_code: wt.error_code,
      metadata: wt.metadata
    }
  end

  def serialize_git_merge(id)
    op = Ai::MergeOperation.joins(:worktree_session)
                           .where(ai_worktree_sessions: { account_id: @account.id })
                           .find(id)

    {
      resource_type: "git_merge",
      source_id: op.id,
      source_type: "Ai::MergeOperation",
      source_label: "Merge Operation",
      name: "#{op.source_branch} → #{op.target_branch}",
      description: "Merge via #{op.strategy} strategy",
      status: op.status,
      created_at: op.created_at,
      pull_request_url: op.pull_request_url,

      # Rich fields
      source_branch: op.source_branch,
      target_branch: op.target_branch,
      strategy: op.strategy,
      merge_commit_sha: op.merge_commit_sha,
      merge_order: op.merge_order,
      has_conflicts: op.has_conflicts,
      conflict_files: op.conflict_files,
      conflict_details: op.conflict_details,
      conflict_resolution: op.conflict_resolution,
      pull_request_id: op.pull_request_id,
      pull_request_status: op.pull_request_status,
      rollback_commit_sha: op.rollback_commit_sha,
      rolled_back: op.rolled_back,
      rolled_back_at: op.rolled_back_at,
      started_at: op.started_at,
      completed_at: op.completed_at,
      duration_ms: op.duration_ms,
      error_message: op.error_message,
      error_code: op.error_code,
      metadata: op.metadata
    }
  end

  def serialize_execution_output(id)
    exec = Ai::TeamExecution.where(account: @account).find(id)

    {
      resource_type: "execution_output",
      source_id: exec.id,
      source_type: "Ai::TeamExecution",
      source_label: "Team Execution",
      name: "Execution #{exec.execution_id}",
      description: "Team execution output (#{exec.status})",
      status: exec.status,
      created_at: exec.created_at,
      execution_id: exec.id,
      team_id: exec.agent_team_id,

      # Rich fields
      objective: exec.objective,
      input_context: exec.input_context,
      output_result: exec.output_result,
      shared_memory: exec.shared_memory,
      performance_metrics: exec.performance_metrics,
      total_cost_usd: exec.total_cost_usd,
      total_tokens_used: exec.total_tokens_used,
      messages_exchanged: exec.messages_exchanged,
      tasks_total: exec.tasks_total,
      tasks_completed: exec.tasks_completed,
      tasks_failed: exec.tasks_failed,
      control_signal: exec.control_signal,
      termination_reason: exec.termination_reason,
      started_at: exec.started_at,
      completed_at: exec.completed_at,
      duration_ms: exec.duration_ms,
      triggered_by_name: exec.triggered_by&.name,
      team_name: exec.agent_team&.name,
      metadata: exec.metadata
    }
  end

  def serialize_shared_memory(id)
    # ID may be composite "pool_id:key" (per-entry) or plain pool UUID (legacy)
    pool_id, entry_key = id.to_s.split(":", 2)
    pool = Ai::MemoryPool.where(account: @account).find(pool_id)

    result = {
      resource_type: "shared_memory",
      source_id: pool.id,
      source_type: "Ai::MemoryPool",
      source_label: pool.name,
      name: entry_key ? "#{pool.name}: #{entry_key}" : pool.name,
      description: "#{pool.pool_type} memory pool (#{pool.scope})",
      status: "available",
      created_at: pool.created_at,
      team_id: pool.team_id,

      # Rich fields
      full_data: entry_key ? { entry_key => pool.data&.dig(entry_key) } : pool.data,
      pool_type: pool.pool_type,
      pool_id: pool.pool_id,
      scope: pool.scope,
      data_size_bytes: pool.data_size_bytes,
      persist_across_executions: pool.persist_across_executions,
      expires_at: pool.expires_at,
      last_accessed_at: pool.last_accessed_at,
      access_control: pool.access_control,
      retention_policy: pool.retention_policy,
      version: pool.version,
      entry_key: entry_key,
      owner_agent_name: pool.owner_agent_id.present? ? Ai::Agent.find_by(id: pool.owner_agent_id)&.name : nil,
      team_name: pool.team_id.present? ? Ai::AgentTeam.find_by(id: pool.team_id)&.name : nil,
      metadata: pool.metadata
    }

    result
  end

  def serialize_trajectory(id)
    traj = Ai::Trajectory.where(account: @account).includes(:chapters).find(id)

    {
      resource_type: "trajectory",
      source_id: traj.id,
      source_type: "Ai::Trajectory",
      source_label: "Trajectory",
      name: traj.title,
      description: "#{traj.trajectory_type} trajectory (#{traj.chapter_count} chapters)",
      status: traj.status,
      created_at: traj.created_at,
      agent_id: traj.ai_agent_id,

      # Rich fields
      summary: traj.summary,
      trajectory_type: traj.trajectory_type,
      trajectory_id: traj.trajectory_id,
      quality_score: traj.quality_score,
      access_count: traj.access_count,
      chapter_count: traj.chapter_count,
      outcome_summary: traj.outcome_summary,
      tags: traj.tags,
      agent_name: traj.ai_agent&.name,
      chapters: traj.chapters.order(:chapter_number).map do |ch|
        {
          chapter_number: ch.chapter_number,
          title: ch.title,
          chapter_type: ch.chapter_type,
          content: ch.content,
          reasoning: ch.reasoning,
          key_decisions: ch.key_decisions,
          artifacts: ch.artifacts,
          context_references: ch.context_references,
          duration_ms: ch.duration_ms
        }
      end,
      metadata: traj.metadata
    }
  end

  def serialize_review(id)
    review = Ai::TaskReview.where(account: @account).find(id)

    {
      resource_type: "review",
      source_id: review.id,
      source_type: "Ai::TaskReview",
      source_label: "Task Review",
      name: "Review #{review.review_id}",
      description: "#{review.review_mode} review (#{review.status})",
      status: review.status,
      created_at: review.created_at,
      agent_id: review.reviewer_agent_id,

      # Rich fields
      review_mode: review.review_mode,
      quality_score: review.quality_score,
      findings: review.findings,
      diff_analysis: review.diff_analysis,
      file_comments: review.file_comments,
      code_suggestions: review.code_suggestions,
      completeness_checks: review.completeness_checks,
      approval_notes: review.approval_notes,
      rejection_reason: review.rejection_reason,
      commit_sha: review.commit_sha,
      repository_url: review.repository_url,
      pull_request_number: review.pull_request_number,
      review_duration_ms: review.review_duration_ms,
      revision_count: review.revision_count,
      reviewer_agent_name: review.reviewer_agent&.name,
      findings_count: review.findings&.count,
      metadata: review.metadata
    }
  end

  def serialize_runner_job(id)
    dispatch = Ai::RunnerDispatch.where(account: @account).find(id)

    {
      resource_type: "runner_job",
      source_id: dispatch.id,
      source_type: "Ai::RunnerDispatch",
      source_label: "Runner Dispatch",
      name: dispatch.git_runner&.name || "Runner Job",
      description: "Workflow run #{dispatch.workflow_run_id}",
      status: dispatch.status,
      created_at: dispatch.created_at,
      url: dispatch.workflow_url,

      # Rich fields
      input_params: dispatch.input_params,
      output_result: dispatch.output_result,
      logs: dispatch.logs,
      runner_labels: dispatch.runner_labels,
      workflow_run_id: dispatch.workflow_run_id,
      workflow_url: dispatch.workflow_url,
      duration_ms: dispatch.duration_ms,
      dispatched_at: dispatch.dispatched_at,
      completed_at: dispatch.completed_at,
      runner_name: dispatch.git_runner&.name,
      repository_name: dispatch.git_repository&.name,
      worktree_branch: dispatch.worktree&.branch_name,
      metadata: {}
    }
  end
end
