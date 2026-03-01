# frozen_string_literal: true

module Ai
  module Teams
    class ExecutionService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # ============================================================================
      # EXECUTION MANAGEMENT
      # ============================================================================

      def start_execution(team_id, params, user: nil)
        team = find_team(team_id)

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
        team = find_team(team_id)
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
        if params[:from_role_id].present? || params[:to_role_id].present?
          from_role = params[:from_role_id].present? ? execution.agent_team.ai_team_roles.find(params[:from_role_id]) : nil
          to_role = params[:to_role_id].present? ? execution.agent_team.ai_team_roles.find(params[:to_role_id]) : nil
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

      private

      def find_team(team_id)
        account.ai_agent_teams.find(team_id)
      end

      def authority_for(team)
        @authority_cache ||= {}
        @authority_cache[team.id] ||= Ai::TeamAuthorityService.new(team: team)
      end
    end
  end
end
