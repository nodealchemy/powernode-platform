# frozen_string_literal: true

class Ai::ExecutionResourceAggregatorService
  RESOURCE_TYPES = %w[artifact git_branch git_merge execution_output shared_memory trajectory review runner_job].freeze

  def initialize(account:)
    @account = account
  end

  def aggregate(filters = {})
    resources = []
    types = filters[:type].present? ? [filters[:type]] : RESOURCE_TYPES

    types.each do |type|
      resources.concat(send("collect_#{type}", filters))
    rescue NoMethodError
      next
    end

    resources = apply_common_filters(resources, filters)
    resources.sort_by { |r| r[:created_at] || Time.at(0) }.reverse
  end

  def counts(filters = {})
    result = { total: 0 }
    RESOURCE_TYPES.each do |type|
      count = send("collect_#{type}", filters).count
      result[type.to_sym] = count
      result[:total] += count
    rescue NoMethodError
      result[type.to_sym] = 0
    end
    result
  end

  private

  def collect_artifact(filters)
    scope = Ai::A2aTask.where(account: @account).where.not(artifacts: nil)
    scope = scope.where(ai_workflow_run_id: execution_run_ids(filters[:execution_id])) if filters[:execution_id]

    scope.flat_map do |task|
      (task.artifacts || []).map do |artifact|
        build_resource(
          resource_type: "artifact",
          name: artifact["name"] || "Unnamed artifact",
          description: artifact.dig("parts", 0, "text")&.truncate(200),
          mime_type: artifact["mime_type"],
          status: "available",
          source_type: "Ai::A2aTask",
          source_id: task.id,
          source_label: "A2A Task #{task.task_id}",
          agent_id: task.to_agent_id,
          preview: artifact.dig("parts", 0, "text")&.truncate(500),
          url: artifact["uri"],
          created_at: task.created_at,
          metadata: artifact
        )
      end
    end
  end

  def collect_git_branch(filters)
    scope = Ai::Worktree.joins(:worktree_session)
                        .where(worktree_sessions: { account_id: @account.id })
    scope = apply_worktree_filters(scope, filters)

    scope.map do |wt|
      build_resource(
        resource_type: "git_branch",
        name: wt.branch_name,
        description: "Worktree branch for #{wt.agent_name || 'agent'}",
        status: wt.status,
        source_type: "Ai::Worktree",
        source_id: wt.id,
        source_label: "Worktree Session",
        agent_id: wt.ai_agent_id,
        agent_name: wt.agent_name,
        branch_name: wt.branch_name,
        commit_sha: wt.head_commit_sha,
        files_changed: wt.files_changed,
        lines_added: wt.lines_added,
        lines_removed: wt.lines_removed,
        created_at: wt.created_at
      )
    end
  end

  def collect_git_merge(filters)
    scope = Ai::MergeOperation.joins(:worktree_session)
                              .where(ai_worktree_sessions: { account_id: @account.id })

    scope.map do |op|
      build_resource(
        resource_type: "git_merge",
        name: "#{op.source_branch} → #{op.target_branch}",
        description: "Merge via #{op.merge_strategy} strategy",
        status: op.status,
        source_type: "Ai::MergeOperation",
        source_id: op.id,
        source_label: "Merge Operation",
        pull_request_url: op.pull_request_url,
        created_at: op.created_at,
        metadata: { strategy: op.merge_strategy, conflict_count: op.conflict_count }
      )
    end
  end

  def collect_execution_output(filters)
    scope = Ai::TeamExecution.where(account: @account)
    scope = scope.where(id: filters[:execution_id]) if filters[:execution_id]
    scope = scope.where(agent_team_id: filters[:team_id]) if filters[:team_id]

    scope.where.not(output_result: nil).map do |exec|
      build_resource(
        resource_type: "execution_output",
        name: "Execution #{exec.execution_id}",
        description: "Team execution output (#{exec.status})",
        status: exec.status,
        source_type: "Ai::TeamExecution",
        source_id: exec.id,
        source_label: "Team Execution",
        execution_id: exec.id,
        team_id: exec.agent_team_id,
        preview: exec.output_result.to_json.truncate(500),
        created_at: exec.created_at,
        metadata: { tasks_total: exec.tasks_total, tasks_completed: exec.tasks_completed }
      )
    end
  end

  def collect_shared_memory(filters)
    scope = Ai::MemoryPool.where(account: @account).where(scope: "persistent")
    scope = scope.where(team_id: filters[:team_id]) if filters[:team_id]

    scope.flat_map do |pool|
      (pool.data || {}).map do |key, value|
        build_resource(
          resource_type: "shared_memory",
          name: "#{pool.name}: #{key}",
          description: "Persistent memory entry",
          status: "available",
          source_type: "Ai::MemoryPool",
          source_id: pool.id,
          source_label: pool.name,
          team_id: pool.team_id,
          preview: value.to_json.truncate(500),
          url: detect_url(value),
          created_at: pool.updated_at,
          metadata: { pool_id: pool.pool_id, version: pool.version }
        )
      end
    end
  end

  def collect_trajectory(filters)
    scope = Ai::Trajectory.where(account: @account)
    scope = scope.where(ai_agent_id: filters[:agent_id]) if filters[:agent_id]

    scope.map do |traj|
      build_resource(
        resource_type: "trajectory",
        name: traj.title,
        description: "#{traj.trajectory_type} trajectory (#{traj.chapter_count} chapters)",
        status: traj.status,
        source_type: "Ai::Trajectory",
        source_id: traj.id,
        source_label: "Trajectory",
        agent_id: traj.ai_agent_id,
        quality_score: traj.quality_score,
        created_at: traj.created_at,
        metadata: { trajectory_type: traj.trajectory_type, tags: traj.tags }
      )
    end
  end

  def collect_review(filters)
    scope = Ai::TaskReview.where(account: @account)

    scope.map do |review|
      build_resource(
        resource_type: "review",
        name: "Review #{review.review_id}",
        description: "#{review.review_mode} review (#{review.status})",
        status: review.status,
        source_type: "Ai::TaskReview",
        source_id: review.id,
        source_label: "Task Review",
        agent_id: review.reviewer_agent_id,
        quality_score: review.findings&.count,
        findings_count: review.findings&.count,
        created_at: review.created_at,
        metadata: { review_mode: review.review_mode, revision_count: review.revision_count }
      )
    end
  end

  def collect_runner_job(filters)
    scope = Ai::RunnerDispatch.where(account: @account)
    scope = scope.joins(:worktree_session) if filters[:execution_id]

    scope.map do |dispatch|
      build_resource(
        resource_type: "runner_job",
        name: dispatch.git_runner&.name || "Runner Job",
        description: "Workflow run #{dispatch.workflow_run_id}",
        status: dispatch.status,
        source_type: "Ai::RunnerDispatch",
        source_id: dispatch.id,
        source_label: "Runner Dispatch",
        url: dispatch.workflow_url,
        created_at: dispatch.created_at,
        metadata: {
          runner_labels: dispatch.runner_labels,
          duration_ms: dispatch.duration_ms,
          workflow_run_id: dispatch.workflow_run_id
        }
      )
    end
  end

  def build_resource(attrs)
    {
      id: attrs[:source_id],
      resource_type: attrs[:resource_type],
      name: attrs[:name],
      description: attrs[:description],
      mime_type: attrs[:mime_type],
      status: attrs[:status],
      source_type: attrs[:source_type],
      source_id: attrs[:source_id],
      source_label: attrs[:source_label],
      execution_id: attrs[:execution_id],
      team_id: attrs[:team_id],
      agent_id: attrs[:agent_id],
      agent_name: attrs[:agent_name],
      preview: attrs[:preview],
      url: attrs[:url],
      branch_name: attrs[:branch_name],
      commit_sha: attrs[:commit_sha],
      files_changed: attrs[:files_changed],
      lines_added: attrs[:lines_added],
      lines_removed: attrs[:lines_removed],
      pull_request_url: attrs[:pull_request_url],
      quality_score: attrs[:quality_score],
      findings_count: attrs[:findings_count],
      created_at: attrs[:created_at],
      metadata: attrs[:metadata] || {}
    }
  end

  def apply_common_filters(resources, filters)
    if filters[:search].present?
      query = filters[:search].downcase
      resources = resources.select { |r| r[:name]&.downcase&.include?(query) || r[:description]&.downcase&.include?(query) }
    end
    resources = resources.select { |r| r[:status] == filters[:status] } if filters[:status].present?
    resources = resources.select { |r| r[:agent_id] == filters[:agent_id] } if filters[:agent_id].present?
    resources = resources.select { |r| r[:team_id] == filters[:team_id] } if filters[:team_id].present?

    if filters[:start_date].present?
      start_date = Time.parse(filters[:start_date]) rescue nil
      resources = resources.select { |r| r[:created_at] && r[:created_at] >= start_date } if start_date
    end
    if filters[:end_date].present?
      end_date = Time.parse(filters[:end_date]) rescue nil
      resources = resources.select { |r| r[:created_at] && r[:created_at] <= end_date } if end_date
    end

    resources
  end

  def apply_worktree_filters(scope, filters)
    scope = scope.where(ai_agent_id: filters[:agent_id]) if filters[:agent_id]
    scope
  end

  def execution_run_ids(execution_id)
    return nil unless execution_id
    Ai::WorkflowRun.where(id: execution_id).pluck(:id)
  end

  def detect_url(value)
    return nil unless value.is_a?(String)
    value.match?(%r{https?://}) ? value : nil
  end
end
