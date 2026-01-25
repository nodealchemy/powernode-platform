# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TeamsController < ApplicationController
        before_action :authenticate_request
        before_action :set_team_service
        before_action :set_team, only: %i[
          show update destroy
          list_roles create_role update_role delete_role assign_agent_to_role
          list_channels create_channel
          list_executions
          analytics
        ]
        before_action :set_execution, only: %i[
          show_execution pause_execution resume_execution cancel_execution complete_execution
          create_task list_tasks show_task assign_task start_task complete_task fail_task delegate_task
          send_message list_messages reply_to_message
          execution_details
        ]

        # ============================================================================
        # TEAMS
        # ============================================================================

        # GET /api/v1/ai/teams
        def index
          teams = @team_service.list_teams(filter_params)

          render_success(
            teams: teams.map { |t| serialize_team(t) },
            total_count: teams.total_count
          )
        end

        # GET /api/v1/ai/teams/:id
        def show
          render_success(serialize_team(@team, detailed: true))
        end

        # POST /api/v1/ai/teams
        def create
          team = if params[:template_id].present?
                   @team_service.create_team_from_template(params[:template_id], name: params[:name], user: current_user)
                 else
                   @team_service.create_team(team_params, user: current_user)
                 end
          render_success(serialize_team(team), status: :created)
        end

        # PATCH /api/v1/ai/teams/:id
        def update
          team = @team_service.update_team(@team.id, team_params)
          render_success(serialize_team(team))
        end

        # DELETE /api/v1/ai/teams/:id
        def destroy
          @team_service.delete_team(@team.id)
          render_success(success: true)
        end

        # ============================================================================
        # ROLES
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/roles
        def list_roles
          roles = @team_service.list_roles(@team.id)
          render_success(roles: roles.map { |r| serialize_role(r) })
        end

        # POST /api/v1/ai/teams/:team_id/roles
        def create_role
          role = @team_service.create_role(@team.id, role_params)
          render_success(serialize_role(role), status: :created)
        end

        # PATCH /api/v1/ai/teams/:team_id/roles/:id
        def update_role
          role = @team_service.update_role(@team.id, params[:id], role_params)
          render_success(serialize_role(role))
        end

        # DELETE /api/v1/ai/teams/:team_id/roles/:id
        def delete_role
          @team_service.delete_role(@team.id, params[:id])
          render_success(success: true)
        end

        # POST /api/v1/ai/teams/:team_id/roles/:id/assign_agent
        def assign_agent_to_role
          role = @team_service.assign_agent_to_role(@team.id, params[:id], params[:agent_id])
          render_success(serialize_role(role))
        end

        # ============================================================================
        # CHANNELS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/channels
        def list_channels
          channels = @team_service.list_channels(@team.id)
          render_success(channels: channels.map { |c| serialize_channel(c) })
        end

        # POST /api/v1/ai/teams/:team_id/channels
        def create_channel
          channel = @team_service.create_channel(@team.id, channel_params)
          render_success(serialize_channel(channel), status: :created)
        end

        # ============================================================================
        # EXECUTIONS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/executions
        def list_executions
          executions = @team_service.list_executions(@team.id, filter_params)

          render_success(
            executions: executions.map { |e| serialize_execution(e) },
            total_count: executions.total_count
          )
        end

        # POST /api/v1/ai/teams/:team_id/executions
        def start_execution
          team = @team_service.get_team(params[:team_id])
          execution = @team_service.start_execution(team.id, execution_params, user: current_user)
          render_success(serialize_execution(execution, detailed: true), status: :created)
        end

        # GET /api/v1/ai/teams/executions/:id
        def show_execution
          render_success(serialize_execution(@execution, detailed: true))
        end

        # POST /api/v1/ai/teams/executions/:id/pause
        def pause_execution
          execution = @team_service.pause_execution(@execution.id)
          render_success(serialize_execution(execution))
        end

        # POST /api/v1/ai/teams/executions/:id/resume
        def resume_execution
          execution = @team_service.resume_execution(@execution.id)
          render_success(serialize_execution(execution))
        end

        # POST /api/v1/ai/teams/executions/:id/cancel
        def cancel_execution
          execution = @team_service.cancel_execution(@execution.id, reason: params[:reason])
          render_success(serialize_execution(execution))
        end

        # POST /api/v1/ai/teams/executions/:id/complete
        def complete_execution
          execution = @team_service.complete_execution(@execution.id, params[:result] || {})
          render_success(serialize_execution(execution))
        end

        # GET /api/v1/ai/teams/executions/:id/details
        def execution_details
          details = @team_service.get_execution_details(@execution.id)
          render_success(details)
        end

        # ============================================================================
        # TASKS
        # ============================================================================

        # GET /api/v1/ai/teams/executions/:execution_id/tasks
        def list_tasks
          tasks = @execution.tasks.includes(:assigned_role, :assigned_agent)
          render_success(tasks: tasks.map { |t| serialize_task(t) })
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks
        def create_task
          task = @team_service.create_task(@execution.id, task_params)
          render_success(serialize_task(task), status: :created)
        end

        # GET /api/v1/ai/teams/executions/:execution_id/tasks/:id
        def show_task
          task = @team_service.get_task(@execution.id, params[:id])
          render_success(serialize_task(task, detailed: true))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/assign
        def assign_task
          task = @team_service.assign_task(@execution.id, params[:id], role_id: params[:role_id], agent_id: params[:agent_id])
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/start
        def start_task
          task = @team_service.start_task(@execution.id, params[:id])
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/complete
        def complete_task
          task = @team_service.complete_task(@execution.id, params[:id], output: params[:output] || {})
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/fail
        def fail_task
          task = @team_service.fail_task(@execution.id, params[:id], reason: params[:reason])
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/delegate
        def delegate_task
          new_task = @team_service.delegate_task(@execution.id, params[:id], to_role_id: params[:to_role_id], to_agent_id: params[:to_agent_id])
          render_success(serialize_task(new_task))
        end

        # ============================================================================
        # MESSAGES
        # ============================================================================

        # GET /api/v1/ai/teams/executions/:execution_id/messages
        def list_messages
          messages = @team_service.get_messages(@execution.id, message_filter_params)
          render_success(messages: messages.map { |m| serialize_message(m) })
        end

        # POST /api/v1/ai/teams/executions/:execution_id/messages
        def send_message
          message = @team_service.send_message(@execution.id, message_params)
          render_success(serialize_message(message), status: :created)
        end

        # POST /api/v1/ai/teams/executions/:execution_id/messages/:id/reply
        def reply_to_message
          reply = @team_service.reply_to_message(@execution.id, params[:id], reply_params)
          render_success(serialize_message(reply))
        end

        # ============================================================================
        # TEMPLATES
        # ============================================================================

        # GET /api/v1/ai/teams/templates
        def list_templates
          templates = @team_service.list_templates(template_filter_params)

          render_success(
            templates: templates.map { |t| serialize_template(t) },
            total_count: templates.total_count
          )
        end

        # GET /api/v1/ai/teams/templates/:id
        def show_template
          template = @team_service.get_template(params[:id])
          render_success(serialize_template(template, detailed: true))
        end

        # POST /api/v1/ai/teams/templates
        def create_template
          template = @team_service.create_template(template_params, user: current_user)
          render_success(serialize_template(template), status: :created)
        end

        # POST /api/v1/ai/teams/templates/:id/publish
        def publish_template
          template = @team_service.publish_template(params[:id])
          render_success(serialize_template(template))
        end

        # ============================================================================
        # ANALYTICS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/analytics
        def analytics
          period_days = params[:period_days]&.to_i || 30
          analytics = @team_service.get_team_analytics(@team.id, period_days: period_days)
          render_success(analytics)
        end

        private

        def set_team_service
          @team_service = ::Ai::TeamOrchestrationService.new(current_account)
        end

        def set_team
          @team = @team_service.get_team(params[:team_id] || params[:id])
        end

        def set_execution
          @execution = @team_service.get_execution(params[:execution_id] || params[:id])
        end

        def filter_params
          params.permit(:status, :topology, :page, :per_page)
        end

        def team_params
          params.permit(
            :name, :description, :goal_description, :team_type,
            :team_topology, :coordination_strategy, :communication_pattern,
            :max_parallel_tasks, :task_timeout_seconds, :status,
            escalation_policy: {}, shared_memory_config: {},
            human_checkpoint_config: {}, team_config: {}
          )
        end

        def role_params
          params.permit(
            :role_name, :role_type, :role_description, :responsibilities,
            :goals, :priority_order, :can_delegate, :can_escalate,
            :max_concurrent_tasks, :agent_id,
            capabilities: [], constraints: [], tools_allowed: [], context_access: {}
          )
        end

        def channel_params
          params.permit(
            :name, :channel_type, :description, :is_persistent,
            :message_retention_hours, participant_roles: [],
            message_schema: {}, routing_rules: {}
          )
        end

        def execution_params
          params.permit(
            :objective, :workflow_run_id, input_context: {},
            tasks: [:description, :expected_output, :task_type, :role_id, { input_data: {} }]
          )
        end

        def task_params
          params.permit(
            :description, :expected_output, :task_type, :priority,
            :max_retries, :parent_task_id, :role_id, input_data: {}
          )
        end

        def message_params
          params.permit(
            :channel_id, :from_role_id, :to_role_id, :task_id,
            :message_type, :content, :priority, :requires_response,
            structured_content: {}, attachments: []
          )
        end

        def message_filter_params
          params.permit(:channel_id, :from_role_id, :message_type, :page, :per_page)
        end

        def reply_params
          params.permit(:from_role_id, :content, :message_type)
        end

        def template_filter_params
          params.permit(:public_only, :system_only, :category, :topology, :page, :per_page)
        end

        def template_params
          params.permit(
            :name, :description, :category, :team_topology, :is_public,
            role_definitions: [], channel_definitions: [], tags: [],
            workflow_pattern: {}, default_config: {}
          )
        end

        def serialize_team(team, detailed: false)
          data = {
            id: team.id,
            name: team.name,
            description: team.description,
            status: team.status,
            team_type: team.team_type,
            team_topology: team.team_topology,
            coordination_strategy: team.coordination_strategy,
            communication_pattern: team.communication_pattern,
            max_parallel_tasks: team.max_parallel_tasks,
            created_at: team.created_at
          }

          if detailed
            data[:goal_description] = team.goal_description
            data[:task_timeout_seconds] = team.task_timeout_seconds
            data[:escalation_policy] = team.escalation_policy
            data[:shared_memory_config] = team.shared_memory_config
            data[:human_checkpoint_config] = team.human_checkpoint_config
            data[:team_config] = team.team_config
            data[:roles_count] = team.ai_team_roles.count
            data[:channels_count] = team.ai_team_channels.count
          end

          data
        end

        def serialize_role(role)
          {
            id: role.id,
            role_name: role.role_name,
            role_type: role.role_type,
            role_description: role.role_description,
            responsibilities: role.responsibilities,
            goals: role.goals,
            capabilities: role.capabilities,
            constraints: role.constraints,
            tools_allowed: role.tools_allowed,
            priority_order: role.priority_order,
            can_delegate: role.can_delegate,
            can_escalate: role.can_escalate,
            max_concurrent_tasks: role.max_concurrent_tasks,
            agent_id: role.ai_agent_id,
            agent_name: role.ai_agent&.name
          }
        end

        def serialize_channel(channel)
          {
            id: channel.id,
            name: channel.name,
            channel_type: channel.channel_type,
            description: channel.description,
            is_persistent: channel.is_persistent,
            message_retention_hours: channel.message_retention_hours,
            participant_roles: channel.participant_roles,
            message_count: channel.message_count
          }
        end

        def serialize_execution(execution, detailed: false)
          data = {
            id: execution.id,
            execution_id: execution.execution_id,
            status: execution.status,
            objective: execution.objective,
            tasks_total: execution.tasks_total,
            tasks_completed: execution.tasks_completed,
            tasks_failed: execution.tasks_failed,
            progress_percentage: execution.progress_percentage,
            messages_exchanged: execution.messages_exchanged,
            total_tokens_used: execution.total_tokens_used,
            total_cost_usd: execution.total_cost_usd,
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            duration_ms: execution.duration_ms,
            created_at: execution.created_at
          }

          if detailed
            data[:input_context] = execution.input_context
            data[:output_result] = execution.output_result
            data[:shared_memory] = execution.shared_memory
            data[:termination_reason] = execution.termination_reason
            data[:performance_metrics] = execution.performance_metrics
          end

          data
        end

        def serialize_task(task, detailed: false)
          data = {
            id: task.id,
            task_id: task.task_id,
            description: task.description,
            status: task.status,
            task_type: task.task_type,
            priority: task.priority,
            assigned_role_id: task.assigned_role_id,
            assigned_role_name: task.assigned_role&.role_name,
            assigned_agent_id: task.assigned_agent_id,
            tokens_used: task.tokens_used,
            cost_usd: task.cost_usd,
            retry_count: task.retry_count,
            started_at: task.started_at,
            completed_at: task.completed_at,
            duration_ms: task.duration_ms
          }

          if detailed
            data[:expected_output] = task.expected_output
            data[:input_data] = task.input_data
            data[:output_data] = task.output_data
            data[:tools_used] = task.tools_used
            data[:failure_reason] = task.failure_reason
            data[:parent_task_id] = task.parent_task_id
          end

          data
        end

        def serialize_message(message)
          {
            id: message.id,
            sequence_number: message.sequence_number,
            message_type: message.message_type,
            content: message.content,
            from_role_id: message.from_role_id,
            from_role_name: message.from_role&.role_name,
            to_role_id: message.to_role_id,
            to_role_name: message.to_role&.role_name,
            channel_id: message.channel_id,
            priority: message.priority,
            requires_response: message.requires_response,
            responded_at: message.responded_at,
            created_at: message.created_at
          }
        end

        def serialize_template(template, detailed: false)
          data = {
            id: template.id,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.category,
            team_topology: template.team_topology,
            is_system: template.is_system,
            is_public: template.is_public,
            usage_count: template.usage_count,
            average_rating: template.average_rating,
            published_at: template.published_at,
            tags: template.tags
          }

          if detailed
            data[:role_definitions] = template.role_definitions
            data[:channel_definitions] = template.channel_definitions
            data[:workflow_pattern] = template.workflow_pattern
            data[:default_config] = template.default_config
          end

          data
        end
      end
    end
  end
end
