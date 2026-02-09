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
    # COMPOSITION HEALTH
    # ============================================================================

    def composition_health(team_id)
      team = get_team(team_id)
      members = team.members.includes(:agent)
      lead_count = members.where(role: "manager").or(members.where(is_lead: true)).count
      worker_count = members.where.not(role: "manager").where(is_lead: false).count
      total = members.count
      ratio = lead_count.positive? ? (worker_count.to_f / lead_count).round(1) : worker_count.to_f

      warnings = []
      recommendations = []

      if team.team_topology == "hierarchical" && lead_count.zero? && total.positive?
        warnings << "Hierarchical team has no lead/manager role"
        recommendations << "Assign a manager role to coordinate workers"
      end

      if lead_count.positive?
        if ratio > 9
          warnings << "Workers-per-lead ratio is #{ratio}:1 (unhealthy)"
          recommendations << "Add more leads or reduce workers"
        elsif ratio > 5
          warnings << "Workers-per-lead ratio is #{ratio}:1 (needs attention)"
        end
      end

      if team.team_topology == "pipeline" && total < 2
        warnings << "Pipeline teams need at least 2 members"
        recommendations << "Add more members for meaningful pipeline execution"
      end

      unless members.where(role: "reviewer").exists?
        recommendations << "Consider adding a reviewer role for quality assurance"
      end

      status = if warnings.empty?
                 "healthy"
      elsif warnings.any? { |w| w.include?("unhealthy") }
                 "unhealthy"
      else
                 "warning"
      end

      {
        status: status,
        member_count: total,
        lead_count: lead_count,
        worker_count: worker_count,
        workers_per_lead: ratio,
        warnings: warnings,
        recommendations: recommendations
      }
    end

    # ============================================================================
    # ROLE PROFILES
    # ============================================================================

    def list_role_profiles(filters = {})
      profiles = Ai::RoleProfile.for_account(account.id)
      profiles = profiles.by_role_type(filters[:role_type]) if filters[:role_type].present?
      profiles = profiles.system_profiles if filters[:is_system]
      profiles.order(:name)
    end

    def get_role_profile(profile_id)
      Ai::RoleProfile.for_account(account.id).find(profile_id)
    end

    def apply_role_profile(team_id, role_id, profile_id)
      team = get_team(team_id)
      role = team.ai_team_roles.find(role_id)
      profile = Ai::RoleProfile.for_account(account.id).find(profile_id)
      profile.apply_to_role(role)
      role
    end

    # ============================================================================
    # TRAJECTORIES
    # ============================================================================

    def list_trajectories(filters = {})
      Ai::TrajectoryService.new(account: account).list_trajectories(filters)
    end

    def get_trajectory(trajectory_id)
      Ai::TrajectoryService.new(account: account).get_trajectory(trajectory_id)
    end

    def search_trajectories(query, filters = {})
      Ai::TrajectoryService.new(account: account).search_relevant(
        query: query,
        agent_id: filters[:agent_id],
        tags: filters[:tags],
        limit: filters[:limit] || 10
      )
    end

    # ============================================================================
    # REVIEWS
    # ============================================================================

    def list_task_reviews(task_id)
      Ai::ReviewWorkflowService.new(account: account).list_reviews(task_id)
    end

    def get_task_review(review_id)
      Ai::ReviewWorkflowService.new(account: account).get_review(review_id)
    end

    def process_review(review_id, action:, notes: nil)
      review_service = Ai::ReviewWorkflowService.new(account: account)
      review = review_service.get_review(review_id)
      review_service.process_review(review, result: action, notes: notes)
    end

    def configure_team_review(team_id, config)
      team = get_team(team_id)
      team.update!(review_config: config)
      team
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
      execs = team.team_executions
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
      execution.tasks.find_by(task_id: task_id) || execution.tasks.find(task_id)
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
      from_role = task.assigned_role
      to_role = execution.agent_team.ai_team_roles.find(to_role_id)
      to_agent = to_agent_id.present? ? account.ai_agents.find(to_agent_id) : to_role.ai_agent

      # Enforce authority: delegation must flow downward
      if from_role
        authority_for(execution.agent_team).authorize_delegation!(from_role, to_role)
      end

      task.delegate!(to_role: to_role, to_agent: to_agent)
    end

    # ============================================================================
    # MESSAGING
    # ============================================================================

    def send_message(execution_id, params)
      execution = get_execution(execution_id)

      # Enforce authority on message direction
      if params[:from_role_id].present? && params[:to_role_id].present?
        from_role = execution.agent_team.ai_team_roles.find_by(id: params[:from_role_id])
        to_role = execution.agent_team.ai_team_roles.find_by(id: params[:to_role_id])
        if from_role && to_role
          authority_for(execution.agent_team).authorize_message!(from_role, to_role, params[:message_type])
        end
      end

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

      executions = team.team_executions.where("created_at >= ?", start_date)
      tasks = Ai::TeamTask.joins(:team_execution).where(ai_team_executions: { agent_team_id: team.id }).where("ai_team_tasks.created_at >= ?", start_date)
      messages = Ai::TeamMessage.joins(:team_execution).where(ai_team_executions: { agent_team_id: team.id }).where("ai_team_messages.created_at >= ?", start_date)
      reviews = Ai::TaskReview.joins(team_task: :team_execution).where(ai_team_executions: { agent_team_id: team.id }).where("ai_task_reviews.created_at >= ?", start_date)
      learnings = team.compound_learnings.where(status: "active")

      completed_execs = executions.where(status: "completed")
      failed_execs = executions.where(status: "failed")
      cancelled_execs = executions.where(status: "cancelled")
      active_execs = executions.where(status: %w[running paused pending])
      total_exec_count = executions.count

      {
        period_days: period_days,
        generated_at: Time.current.iso8601,

        overview: {
          total_executions: total_exec_count,
          completed_executions: completed_execs.count,
          failed_executions: failed_execs.count,
          cancelled_executions: cancelled_execs.count,
          active_executions: active_execs.count,
          success_rate: calculate_success_rate(executions),
          total_tasks: tasks.count,
          completed_tasks: tasks.where(status: "completed").count,
          failed_tasks: tasks.where(status: "failed").count,
          total_messages: messages.count,
          total_tokens_used: executions.sum(:total_tokens_used),
          total_cost_usd: executions.sum(:total_cost_usd).to_f.round(4),
          executions_by_day: executions.group_by_day(:created_at).count,
          cost_by_day: completed_execs.group_by_day(:created_at).sum(:total_cost_usd)
        },

        performance: build_performance_analytics(executions, completed_execs, tasks, messages, total_exec_count),
        cost: build_cost_analytics(executions, completed_execs, tasks, messages, total_exec_count),
        agents: build_agent_analytics(team, tasks, messages),
        communication: build_communication_analytics(messages, team),
        quality: build_quality_analytics(reviews, learnings)
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

    def authority_for(team)
      @authority_cache ||= {}
      @authority_cache[team.id] ||= Ai::TeamAuthorityService.new(team: team)
    end

    def build_performance_analytics(executions, completed_execs, tasks, messages, total_exec_count)
      durations = completed_execs.where.not(duration_ms: nil).pluck(:duration_ms).sort

      {
        avg_duration_ms: completed_execs.average(:duration_ms)&.round(2),
        median_duration_ms: calculate_percentile(durations, 50),
        p95_duration_ms: calculate_percentile(durations, 95),
        min_duration_ms: durations.first,
        max_duration_ms: durations.last,
        avg_tasks_per_execution: total_exec_count.positive? ? (tasks.count.to_f / total_exec_count).round(2) : 0,
        avg_messages_per_execution: total_exec_count.positive? ? (messages.count.to_f / total_exec_count).round(2) : 0,
        throughput_per_day: total_exec_count.positive? ? (completed_execs.count.to_f / [(executions.maximum(:created_at).to_date - executions.minimum(:created_at).to_date).to_i, 1].max).round(2) : 0,
        status_breakdown: executions.group(:status).count,
        termination_reasons: executions.where.not(termination_reason: [nil, ""]).group(:termination_reason).count,
        duration_by_day: completed_execs.group_by_day(:created_at).average(:duration_ms),
        slowest_executions: completed_execs.where.not(duration_ms: nil).order(duration_ms: :desc).limit(5).map { |e|
          { id: e.id, execution_id: e.execution_id, objective: e.objective&.truncate(100), duration_ms: e.duration_ms, tasks_total: e.tasks_total, created_at: e.created_at.iso8601 }
        }
      }
    end

    def build_cost_analytics(executions, completed_execs, tasks, messages, total_exec_count)
      total_cost = executions.sum(:total_cost_usd).to_f
      total_tokens = executions.sum(:total_tokens_used)
      tasks_count = tasks.count
      messages_count = messages.count

      {
        total_cost_usd: total_cost.round(4),
        total_tokens: total_tokens,
        avg_cost_per_execution: total_exec_count.positive? ? (total_cost / total_exec_count).round(4) : 0,
        avg_tokens_per_execution: total_exec_count.positive? ? (total_tokens.to_f / total_exec_count).round(0) : 0,
        cost_by_day: executions.group_by_day(:created_at).sum(:total_cost_usd),
        tokens_by_day: executions.group_by_day(:created_at).sum(:total_tokens_used),
        cost_by_status: executions.group(:status).sum(:total_cost_usd),
        tokens_by_status: executions.group(:status).sum(:total_tokens_used),
        top_cost_executions: executions.where("total_cost_usd > 0").order(total_cost_usd: :desc).limit(5).map { |e|
          { id: e.id, execution_id: e.execution_id, objective: e.objective&.truncate(100), cost_usd: e.total_cost_usd.to_f.round(4), tokens: e.total_tokens_used, created_at: e.created_at.iso8601 }
        },
        cost_per_task: tasks_count.positive? ? (total_cost / tasks_count).round(4) : 0,
        cost_per_message: messages_count.positive? ? (total_cost / messages_count).round(6) : 0
      }
    end

    def build_agent_analytics(team, tasks, messages)
      roles = team.ai_team_roles.includes(:ai_agent)
      role_stats = roles.map do |role|
        role_tasks = tasks.where(assigned_role_id: role.id)
        role_msgs_sent = messages.where(from_role_id: role.id)
        role_msgs_received = messages.where(to_role_id: role.id)

        tools_hash = {}
        role_tasks.where.not(tools_used: nil).pluck(:tools_used).each do |tools|
          Array(tools).each { |t| tools_hash[t] = (tools_hash[t] || 0) + 1 }
        end

        completed_count = role_tasks.where(status: "completed").count
        total_finished = role_tasks.where(status: %w[completed failed]).count

        {
          role_id: role.id,
          role_name: role.role_name,
          role_type: role.role_type,
          agent_name: role.ai_agent&.name,
          tasks_total: role_tasks.count,
          tasks_completed: completed_count,
          tasks_failed: role_tasks.where(status: "failed").count,
          success_rate: total_finished.positive? ? ((completed_count.to_f / total_finished) * 100).round(2) : 0,
          avg_duration_ms: role_tasks.where.not(duration_ms: nil).average(:duration_ms)&.round(2),
          total_tokens: role_tasks.sum(:tokens_used),
          total_cost_usd: role_tasks.sum(:cost_usd).to_f.round(4),
          messages_sent: role_msgs_sent.count,
          messages_received: role_msgs_received.count,
          tools_used: tools_hash,
          avg_retries: role_tasks.average(:retry_count)&.round(2) || 0
        }
      end

      all_tools = {}
      role_stats.each { |rs| rs[:tools_used].each { |t, c| all_tools[t] = (all_tools[t] || 0) + c } }

      {
        role_stats: role_stats,
        task_type_distribution: tasks.group(:task_type).count,
        workload_by_role: role_stats.each_with_object({}) { |rs, h| h[rs[:role_name]] = rs[:tasks_total] },
        unassigned_tasks: tasks.where(assigned_role_id: nil).count,
        top_tools: all_tools.sort_by { |_, c| -c }.first(10).to_h
      }
    end

    def build_communication_analytics(messages, team)
      total = messages.count
      escalations = messages.where(message_type: "escalation")
      questions = messages.where(message_type: "question")
      answers = messages.where(message_type: "answer")
      requiring_response = messages.where(requires_response: true)
      responded = requiring_response.where.not(responded_at: nil)
      pending = requiring_response.where(responded_at: nil)

      avg_response_seconds = if responded.exists?
                               responded
                                 .where.not(responded_at: nil)
                                 .pick(Arel.sql("AVG(EXTRACT(EPOCH FROM (ai_team_messages.responded_at - ai_team_messages.created_at)))"))
                                 &.round(2)
                             end

      # Role interaction matrix
      interactions = messages
        .where.not(from_role_id: nil)
        .where.not(to_role_id: nil)
        .group(:from_role_id, :to_role_id)
        .count

      role_names = team.ai_team_roles.pluck(:id, :role_name).to_h
      role_interactions = interactions.map do |(from_id, to_id), count|
        { from: role_names[from_id] || from_id, to: role_names[to_id] || to_id, count: count }
      end

      {
        total_messages: total,
        message_type_distribution: messages.group(:message_type).count,
        priority_distribution: messages.group(:priority).count,
        escalation_count: escalations.count,
        escalation_rate: total.positive? ? ((escalations.count.to_f / total) * 100).round(2) : 0,
        questions_asked: questions.count,
        questions_answered: answers.count,
        pending_responses: pending.count,
        response_rate: requiring_response.count.positive? ? ((responded.count.to_f / requiring_response.count) * 100).round(2) : 0,
        avg_response_time_seconds: avg_response_seconds || 0,
        messages_by_day: messages.group_by_day(:created_at).count,
        role_interactions: role_interactions,
        broadcasts_count: messages.where(message_type: "broadcast").count,
        high_priority_count: messages.where(priority: %w[high critical urgent]).count
      }
    end

    def build_quality_analytics(reviews, learnings)
      total_reviews = reviews.count
      approved = reviews.where(status: "approved").count
      rejected = reviews.where(status: "rejected").count
      revision_requested = reviews.where(status: "revision_requested").count
      pending = reviews.where(status: %w[pending in_progress]).count

      # Quality score distribution in buckets
      score_dist = {}
      if reviews.where.not(quality_score: nil).exists?
        reviews.where.not(quality_score: nil).pluck(:quality_score).each do |score|
          bucket = case score
                   when 0..20 then "0-20"
                   when 21..40 then "21-40"
                   when 41..60 then "41-60"
                   when 61..80 then "61-80"
                   else "81-100"
                   end
          score_dist[bucket] = (score_dist[bucket] || 0) + 1
        end
      end

      # Findings aggregation
      findings_by_severity = {}
      findings_by_category = {}
      reviews.where.not(findings: nil).pluck(:findings).each do |findings_arr|
        Array(findings_arr).each do |f|
          sev = f["severity"] || "unknown"
          cat = f["category"] || "unknown"
          findings_by_severity[sev] = (findings_by_severity[sev] || 0) + 1
          findings_by_category[cat] = (findings_by_category[cat] || 0) + 1
        end
      end

      # Learning metrics
      learning_metrics = if learnings.exists?
                           injected = learnings.where("injection_count > 0")
                           {
                             total_learnings: learnings.count,
                             by_category: learnings.group(:category).count,
                             by_extraction_method: learnings.group(:extraction_method).count,
                             avg_importance: learnings.average(:importance_score)&.round(2) || 0,
                             avg_confidence: learnings.average(:confidence_score)&.round(2) || 0,
                             avg_effectiveness: learnings.average(:effectiveness_score)&.round(2) || 0,
                             total_injections: learnings.sum(:injection_count),
                             positive_outcomes: learnings.sum(:positive_outcome_count),
                             negative_outcomes: learnings.sum(:negative_outcome_count),
                             injection_success_rate: injected.count.positive? ? ((injected.where("positive_outcome_count > negative_outcome_count").count.to_f / injected.count) * 100).round(2) : 0,
                             high_importance_count: learnings.where("importance_score >= ?", 0.8).count
                           }
                         else
                           {
                             total_learnings: 0, by_category: {}, by_extraction_method: {},
                             avg_importance: 0, avg_confidence: 0, avg_effectiveness: 0,
                             total_injections: 0, positive_outcomes: 0, negative_outcomes: 0,
                             injection_success_rate: 0, high_importance_count: 0
                           }
                         end

      {
        total_reviews: total_reviews,
        approved_count: approved,
        rejected_count: rejected,
        revision_requested_count: revision_requested,
        pending_count: pending,
        approval_rate: total_reviews.positive? ? ((approved.to_f / total_reviews) * 100).round(2) : 0,
        avg_quality_score: reviews.average(:quality_score)&.round(2) || 0,
        quality_score_distribution: score_dist,
        avg_review_duration_ms: reviews.average(:review_duration_ms)&.round(2) || 0,
        avg_revision_count: reviews.average(:revision_count)&.round(2) || 0,
        review_mode_breakdown: reviews.group(:review_mode).count,
        findings_by_severity: findings_by_severity,
        findings_by_category: findings_by_category,
        learning: learning_metrics
      }
    end

    def calculate_percentile(sorted_values, percentile)
      return nil if sorted_values.empty?

      k = (percentile / 100.0 * (sorted_values.length - 1)).round
      sorted_values[k]
    end

    def calculate_success_rate(executions)
      return 0.0 if executions.count.zero?

      completed = executions.completed.count
      total = executions.where(status: %w[completed failed]).count
      return 0.0 if total.zero?

      ((completed.to_f / total) * 100).round(2)
    end
  end
end
