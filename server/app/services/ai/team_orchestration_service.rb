# frozen_string_literal: true

module Ai
  class TeamOrchestrationService
    attr_reader :account

    def initialize(account)
      @account = account
    end

    # ============================================================================
    # TEAM MANAGEMENT
    # ============================================================================

    def list_teams(filters = {})
      teams = account.ai_agent_teams
      teams = teams.where(status: filters[:status]) if filters[:status].present?
      teams = teams.where(team_topology: filters[:topology]) if filters[:topology].present?
      teams = teams.order(created_at: :desc)
      teams = teams.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      teams
    end

    def get_team(team_id)
      account.ai_agent_teams.find(team_id)
    end

    def create_team(params, user: nil)
      account.ai_agent_teams.create!(
        name: params[:name],
        description: params[:description],
        goal_description: params[:goal_description],
        team_type: params[:team_type] || "general",
        team_topology: params[:team_topology] || "hierarchical",
        coordination_strategy: params[:coordination_strategy] || "manager_led",
        communication_pattern: params[:communication_pattern] || "hub_spoke",
        max_parallel_tasks: params[:max_parallel_tasks] || 3,
        task_timeout_seconds: params[:task_timeout_seconds] || 300,
        escalation_policy: params[:escalation_policy] || {},
        shared_memory_config: params[:shared_memory_config] || {},
        human_checkpoint_config: params[:human_checkpoint_config] || {},
        team_config: params[:team_config] || {},
        status: "active"
      )
    end

    def create_team_from_template(template_id, name: nil, user: nil)
      template = Ai::TeamTemplate.find(template_id)
      template.create_team!(account: account, name: name, user: user)
    end

    def update_team(team_id, params)
      team = get_team(team_id)
      team.update!(params.slice(
        :name, :description, :goal_description, :team_topology,
        :coordination_strategy, :communication_pattern, :max_parallel_tasks,
        :task_timeout_seconds, :escalation_policy, :shared_memory_config,
        :human_checkpoint_config, :team_config, :status
      ))
      team
    end

    def delete_team(team_id)
      team = get_team(team_id)
      team.destroy!
    end

    # ============================================================================
    # ROLE MANAGEMENT
    # ============================================================================

    def list_roles(team_id)
      team = get_team(team_id)
      team.ai_team_roles.ordered_by_priority
    end

    def create_role(team_id, params)
      team = get_team(team_id)

      Ai::TeamRole.create!(
        account: account,
        agent_team: team,
        role_name: params[:role_name],
        role_type: params[:role_type] || "worker",
        role_description: params[:role_description],
        responsibilities: params[:responsibilities],
        goals: params[:goals],
        capabilities: params[:capabilities] || [],
        constraints: params[:constraints] || [],
        tools_allowed: params[:tools_allowed] || [],
        priority_order: params[:priority_order] || 0,
        can_delegate: params[:can_delegate] || false,
        can_escalate: params[:can_escalate] || true,
        max_concurrent_tasks: params[:max_concurrent_tasks] || 1,
        context_access: params[:context_access] || {},
        ai_agent_id: params[:agent_id]
      )
    end

    def update_role(team_id, role_id, params)
      team = get_team(team_id)
      role = team.ai_team_roles.find(role_id)
      role.update!(params.slice(
        :role_name, :role_type, :role_description, :responsibilities,
        :goals, :capabilities, :constraints, :tools_allowed, :priority_order,
        :can_delegate, :can_escalate, :max_concurrent_tasks, :context_access
      ))
      role
    end

    def assign_agent_to_role(team_id, role_id, agent_id)
      team = get_team(team_id)
      role = team.ai_team_roles.find(role_id)
      agent = account.ai_agents.find(agent_id)
      role.update!(ai_agent: agent)
      role
    end

    def delete_role(team_id, role_id)
      team = get_team(team_id)
      role = team.ai_team_roles.find(role_id)
      role.destroy!
    end

    # ============================================================================
    # CHANNEL MANAGEMENT
    # ============================================================================

    def list_channels(team_id)
      team = get_team(team_id)
      team.ai_team_channels
    end

    def create_channel(team_id, params)
      team = get_team(team_id)

      Ai::TeamChannel.create!(
        agent_team: team,
        name: params[:name],
        channel_type: params[:channel_type] || "broadcast",
        description: params[:description],
        participant_roles: params[:participant_roles] || [],
        message_schema: params[:message_schema] || {},
        is_persistent: params[:is_persistent] != false,
        message_retention_hours: params[:message_retention_hours],
        routing_rules: params[:routing_rules] || {}
      )
    end

    # ============================================================================
    # EXECUTION MANAGEMENT
    # ============================================================================

    def start_execution(team_id, params, user: nil)
      team = get_team(team_id)

      execution = Ai::TeamExecution.create!(
        account: account,
        agent_team: team,
        triggered_by: user,
        objective: params[:objective],
        input_context: params[:input_context] || {},
        workflow_run_id: params[:workflow_run_id]
      )

      # Create initial tasks based on objective
      if params[:tasks].present?
        params[:tasks].each_with_index do |task_params, idx|
          create_task(execution.id, task_params.merge(priority: idx + 1))
        end
      end

      execution.start!
      execution
    end

    def get_execution(execution_id)
      account.ai_team_executions.find(execution_id)
    end

    def list_executions(team_id, filters = {})
      team = get_team(team_id)
      execs = team.ai_team_executions
      execs = execs.where(status: filters[:status]) if filters[:status].present?
      execs = execs.order(created_at: :desc)
      execs = execs.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      execs
    end

    def pause_execution(execution_id)
      execution = get_execution(execution_id)
      execution.pause!
      execution
    end

    def resume_execution(execution_id)
      execution = get_execution(execution_id)
      execution.resume!
      execution
    end

    def cancel_execution(execution_id, reason: "user_cancelled")
      execution = get_execution(execution_id)
      execution.cancel!(reason)
      execution
    end

    def complete_execution(execution_id, result = {})
      execution = get_execution(execution_id)
      execution.complete!(result)
      execution
    end

    # ============================================================================
    # TASK MANAGEMENT
    # ============================================================================

    def create_task(execution_id, params)
      execution = get_execution(execution_id)

      task = execution.tasks.create!(
        description: params[:description],
        expected_output: params[:expected_output],
        input_data: params[:input_data] || {},
        task_type: params[:task_type] || "execution",
        priority: params[:priority] || 5,
        max_retries: params[:max_retries] || 3,
        parent_task_id: params[:parent_task_id]
      )

      # Auto-assign if role specified
      if params[:role_id].present?
        role = execution.agent_team.ai_team_roles.find(params[:role_id])
        task.assign!(role: role, agent: role.ai_agent)
      end

      task
    end

    def get_task(execution_id, task_id)
      execution = get_execution(execution_id)
      execution.tasks.find_by!(task_id: task_id) || execution.tasks.find(task_id)
    end

    def assign_task(execution_id, task_id, role_id:, agent_id: nil)
      execution = get_execution(execution_id)
      task = execution.tasks.find(task_id)
      role = execution.agent_team.ai_team_roles.find(role_id)
      agent = agent_id.present? ? account.ai_agents.find(agent_id) : role.ai_agent

      task.assign!(role: role, agent: agent)
      task
    end

    def start_task(execution_id, task_id)
      task = get_task(execution_id, task_id)
      task.start!
      task
    end

    def complete_task(execution_id, task_id, output: {})
      task = get_task(execution_id, task_id)
      task.complete!(output)
      task
    end

    def fail_task(execution_id, task_id, reason:)
      task = get_task(execution_id, task_id)
      task.fail!(reason)
      task
    end

    def delegate_task(execution_id, task_id, to_role_id:, to_agent_id: nil)
      execution = get_execution(execution_id)
      task = execution.tasks.find(task_id)
      to_role = execution.agent_team.ai_team_roles.find(to_role_id)
      to_agent = to_agent_id.present? ? account.ai_agents.find(to_agent_id) : to_role.ai_agent

      task.delegate!(to_role: to_role, to_agent: to_agent)
    end

    # ============================================================================
    # MESSAGING
    # ============================================================================

    def send_message(execution_id, params)
      execution = get_execution(execution_id)

      message = execution.messages.create!(
        channel_id: params[:channel_id],
        from_role_id: params[:from_role_id],
        to_role_id: params[:to_role_id],
        task_id: params[:task_id],
        message_type: params[:message_type] || "task_update",
        content: params[:content],
        structured_content: params[:structured_content] || {},
        attachments: params[:attachments] || [],
        priority: params[:priority] || "normal",
        requires_response: params[:requires_response] || false
      )

      message
    end

    def get_messages(execution_id, filters = {})
      execution = get_execution(execution_id)
      messages = execution.messages.ordered
      messages = messages.where(channel_id: filters[:channel_id]) if filters[:channel_id].present?
      messages = messages.where(from_role_id: filters[:from_role_id]) if filters[:from_role_id].present?
      messages = messages.where(message_type: filters[:message_type]) if filters[:message_type].present?
      messages = messages.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      messages
    end

    def reply_to_message(execution_id, message_id, params)
      execution = get_execution(execution_id)
      message = execution.messages.find(message_id)

      message.reply!(
        from: execution.agent_team.ai_team_roles.find(params[:from_role_id]),
        content: params[:content],
        message_type: params[:message_type] || "answer"
      )
    end

    # ============================================================================
    # TEMPLATES
    # ============================================================================

    def list_templates(filters = {})
      templates = Ai::TeamTemplate.all
      templates = templates.public_templates if filters[:public_only]
      templates = templates.system_templates if filters[:system_only]
      templates = templates.by_category(filters[:category]) if filters[:category].present?
      templates = templates.by_topology(filters[:topology]) if filters[:topology].present?
      templates = templates.order(usage_count: :desc)
      templates = templates.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      templates
    end

    def get_template(template_id)
      Ai::TeamTemplate.find(template_id)
    end

    def create_template(params, user: nil)
      Ai::TeamTemplate.create!(
        account: account,
        name: params[:name],
        description: params[:description],
        category: params[:category],
        team_topology: params[:team_topology] || "hierarchical",
        role_definitions: params[:role_definitions] || [],
        channel_definitions: params[:channel_definitions] || [],
        workflow_pattern: params[:workflow_pattern] || {},
        default_config: params[:default_config] || {},
        is_public: params[:is_public] || false,
        tags: params[:tags] || [],
        created_by: user
      )
    end

    def publish_template(template_id)
      template = account.ai_team_templates.find(template_id)
      template.publish!
      template
    end

    # ============================================================================
    # ANALYTICS
    # ============================================================================

    def get_team_analytics(team_id, period_days: 30)
      team = get_team(team_id)
      start_date = period_days.days.ago

      executions = team.ai_team_executions.where("created_at >= ?", start_date)

      {
        total_executions: executions.count,
        completed_executions: executions.completed.count,
        failed_executions: executions.failed.count,
        avg_duration_ms: executions.completed.average(:duration_ms)&.round(2),
        total_tasks: executions.joins(:tasks).count,
        completed_tasks: executions.joins(:tasks).where(ai_team_tasks: { status: "completed" }).count,
        total_messages: executions.joins(:messages).count,
        total_tokens_used: executions.sum(:total_tokens_used),
        total_cost_usd: executions.sum(:total_cost_usd).to_f.round(4),
        executions_by_day: executions.group_by_day(:created_at).count,
        success_rate: calculate_success_rate(executions)
      }
    end

    def get_execution_details(execution_id)
      execution = get_execution(execution_id)

      {
        execution: execution,
        tasks: execution.tasks.includes(:assigned_role, :assigned_agent).order(:created_at),
        messages: execution.messages.includes(:from_role, :to_role, :channel).ordered,
        shared_memory: execution.shared_memory,
        performance: {
          duration_ms: execution.duration_ms,
          tasks_total: execution.tasks_total,
          tasks_completed: execution.tasks_completed,
          tasks_failed: execution.tasks_failed,
          messages_exchanged: execution.messages_exchanged,
          total_tokens: execution.total_tokens_used,
          total_cost: execution.total_cost_usd
        }
      }
    end

    private

    def calculate_success_rate(executions)
      return 0.0 if executions.count.zero?

      completed = executions.completed.count
      total = executions.where(status: %w[completed failed]).count
      return 0.0 if total.zero?

      ((completed.to_f / total) * 100).round(2)
    end
  end
end
