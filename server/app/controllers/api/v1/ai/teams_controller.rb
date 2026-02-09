# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TeamsController < ApplicationController
        rescue_from ::Ai::TeamAuthorityService::AuthorityViolation do |e|
          render_error(e.message, status: :forbidden)
        end

        before_action :authenticate_request
        before_action :set_team_service
        before_action :set_team, only: %i[
          show update destroy
          list_roles create_role update_role delete_role assign_agent_to_role apply_role_profile
          list_channels create_channel show_channel update_channel delete_channel
          list_executions
          analytics
          composition_health
          update_review_config
        ]
        before_action :set_execution, only: %i[
          show_execution pause_execution resume_execution cancel_execution complete_execution
          create_task list_tasks show_task assign_task start_task complete_task fail_task delegate_task
          send_message list_messages reply_to_message
          execution_details
          list_task_reviews
        ]

        # ============================================================================
        # TEAMS
        # ============================================================================

        # GET /api/v1/ai/teams
        def index
          teams = @team_service.list_teams(filter_params)

          render_success(
            teams: teams.map { |t| serialize_team(t) },
            total_count: teams.respond_to?(:total_count) ? teams.total_count : teams.count
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

        # GET /api/v1/ai/teams/:team_id/channels/:id
        def show_channel
          channel = @team_service.get_channel(@team.id, params[:id])
          render_success(serialize_channel(channel))
        end

        # PATCH /api/v1/ai/teams/:team_id/channels/:id
        def update_channel
          channel = @team_service.update_channel(@team.id, params[:id], channel_params)
          render_success(serialize_channel(channel))
        end

        # DELETE /api/v1/ai/teams/:team_id/channels/:id
        def delete_channel
          @team_service.delete_channel(@team.id, params[:id])
          render_success(message: "Channel deleted successfully")
        end

        # POST /api/v1/ai/teams/cleanup_messages
        def cleanup_messages
          channels_processed = 0
          messages_deleted = 0

          current_user.account.ai_agent_teams.find_each do |team|
            team.ai_team_channels.where.not(message_retention_hours: nil).find_each do |channel|
              count_before = channel.messages.count
              channel.cleanup_old_messages!
              count_after = channel.messages.count
              messages_deleted += (count_before - count_after)
              channels_processed += 1
            end
          end

          render_success(
            channels_processed: channels_processed,
            messages_deleted: messages_deleted
          )
        end

        # ============================================================================
        # EXECUTIONS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/executions
        def list_executions
          executions = @team_service.list_executions(@team.id, filter_params)

          render_success(
            executions: executions.map { |e| serialize_execution(e) },
            total_count: executions.respond_to?(:total_count) ? executions.total_count : executions.count
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
            total_count: templates.respond_to?(:total_count) ? templates.total_count : templates.count
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

        # ============================================================================
        # COMPOSITION HEALTH
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/composition_health
        def composition_health
          health = @team_service.composition_health(@team.id)
          render_success(health)
        end

        # ============================================================================
        # ROLE PROFILES
        # ============================================================================

        # GET /api/v1/ai/teams/role_profiles
        def list_role_profiles
          profiles = @team_service.list_role_profiles(role_profile_filter_params)
          render_success(role_profiles: profiles.map { |p| serialize_role_profile(p) })
        end

        # GET /api/v1/ai/teams/role_profiles/:id
        def show_role_profile
          profile = @team_service.get_role_profile(params[:id])
          render_success(serialize_role_profile(profile))
        end

        # POST /api/v1/ai/teams/:team_id/roles/:id/apply_profile
        def apply_role_profile
          role = @team_service.apply_role_profile(@team.id, params[:id], params[:profile_id])
          render_success(serialize_role(role))
        end

        # ============================================================================
        # TRAJECTORIES
        # ============================================================================

        # GET /api/v1/ai/teams/trajectories
        def list_trajectories
          trajectories = @team_service.list_trajectories(trajectory_filter_params)
          render_success(trajectories: trajectories.map { |t| serialize_trajectory(t) })
        end

        # GET /api/v1/ai/teams/trajectories/:id
        def show_trajectory
          trajectory = @team_service.get_trajectory(params[:id])
          render_success(serialize_trajectory(trajectory, detailed: true))
        end

        # GET /api/v1/ai/teams/trajectories/search
        def search_trajectories
          trajectories = @team_service.search_trajectories(
            params[:query],
            trajectory_filter_params
          )
          render_success(trajectories: trajectories.map { |t| serialize_trajectory(t) })
        end

        # ============================================================================
        # REVIEWS
        # ============================================================================

        # GET /api/v1/ai/teams/executions/:execution_id/tasks/:task_id/reviews
        def list_task_reviews
          task = @team_service.get_task(@execution.id, params[:task_id])
          reviews = @team_service.list_task_reviews(task.id)
          render_success(reviews: reviews.map { |r| serialize_review(r) })
        end

        # GET /api/v1/ai/teams/reviews/:id
        def show_review
          review = @team_service.get_task_review(params[:id])
          render_success(serialize_review(review))
        end

        # POST /api/v1/ai/teams/reviews/:id/process
        def process_review
          review = @team_service.process_review(
            params[:id],
            action: params[:action_type],
            notes: params[:notes]
          )
          render_success(serialize_review(review))
        end

        # GET /api/v1/ai/teams/reviews/:review_id/comments
        def list_review_comments
          authorize_code_reviews_read!
          review = current_account.ai_task_reviews.find(params[:review_id])
          comments = review.code_review_comments.ordered
          render_success({ comments: comments.map(&:comment_summary) })
        end

        # POST /api/v1/ai/teams/reviews/:review_id/comments
        def create_review_comment
          authorize_code_reviews_manage!
          review = current_account.ai_task_reviews.find(params[:review_id])
          comment = review.code_review_comments.create!(
            account: current_account,
            **review_comment_params
          )
          render_success({ comment: comment.comment_summary }, status: :created)
        end

        # PATCH /api/v1/ai/teams/reviews/:review_id/comments/:comment_id
        def update_review_comment
          authorize_code_reviews_manage!
          review = current_account.ai_task_reviews.find(params[:review_id])
          comment = review.code_review_comments.find(params[:comment_id])
          comment.update!(review_comment_params)
          render_success({ comment: comment.comment_summary })
        end

        # PUT /api/v1/ai/teams/:team_id/review_config
        def update_review_config
          team = @team_service.configure_team_review(@team.id, review_config_params.to_h)
          render_success(serialize_team(team, detailed: true))
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
          params.require(:channel).permit(
            :name, :channel_type, :description, :is_persistent,
            :message_retention_hours,
            participant_roles: [],
            message_schema: {},
            routing_rules: {},
            metadata: {}
          )
        end

        def execution_params
          params.permit(
            :objective, :workflow_run_id, input_context: {},
            tasks: [ :description, :expected_output, :task_type, :role_id, { input_data: {} } ]
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

        def role_profile_filter_params
          params.permit(:role_type, :is_system)
        end

        def trajectory_filter_params
          params.permit(:type, :status, :query, :limit, :agent_id, tags: [])
        end

        def authorize_code_reviews_read!
          return if current_user.has_permission?("ai.code_reviews.read")

          render_forbidden
        end

        def authorize_code_reviews_manage!
          return if current_user.has_permission?("ai.code_reviews.manage")

          render_forbidden
        end

        def review_comment_params
          params.require(:comment).permit(:file_path, :line_start, :line_end, :comment_type, :severity, :content, :suggested_fix, :category, :resolved)
        end

        def review_config_params
          params.permit(
            :auto_review_enabled, :review_mode, :max_revisions,
            :reviewer_role_type, :quality_threshold,
            review_task_types: []
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
            message_count: channel.message_count,
            routing_rules: channel.routing_rules,
            message_schema: channel.message_schema,
            metadata: channel.metadata,
            created_at: channel.created_at,
            updated_at: channel.updated_at
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
            created_at: message.created_at,
            structured_content: message.structured_content,
            attachments: message.attachments,
            read_at: message.read_at,
            in_reply_to_id: message.in_reply_to_id,
            reply_count: message.replies.count
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

        def serialize_role_profile(profile)
          {
            id: profile.id,
            name: profile.name,
            slug: profile.slug,
            role_type: profile.role_type,
            description: profile.description,
            system_prompt_template: profile.system_prompt_template,
            communication_style: profile.communication_style,
            expected_output_schema: profile.expected_output_schema,
            review_criteria: profile.review_criteria,
            quality_checks: profile.quality_checks,
            delegation_rules: profile.delegation_rules,
            escalation_rules: profile.escalation_rules,
            is_system: profile.is_system,
            metadata: profile.metadata
          }
        end

        def serialize_trajectory(trajectory, detailed: false)
          data = {
            id: trajectory.id,
            trajectory_id: trajectory.trajectory_id,
            title: trajectory.title,
            summary: trajectory.summary,
            status: trajectory.status,
            trajectory_type: trajectory.trajectory_type,
            quality_score: trajectory.quality_score,
            access_count: trajectory.access_count,
            chapter_count: trajectory.chapter_count,
            tags: trajectory.tags,
            outcome_summary: trajectory.outcome_summary,
            created_at: trajectory.created_at
          }

          if detailed
            chapters = trajectory.chapters.loaded? ? trajectory.chapters : trajectory.chapters.includes(:trajectory)
            data[:chapters] = chapters.ordered.map { |c| serialize_chapter(c) }
          end

          data
        end

        def serialize_chapter(chapter)
          {
            id: chapter.id,
            chapter_number: chapter.chapter_number,
            title: chapter.title,
            chapter_type: chapter.chapter_type,
            content: chapter.content,
            reasoning: chapter.reasoning,
            key_decisions: chapter.key_decisions,
            artifacts: chapter.artifacts,
            context_references: chapter.context_references,
            duration_ms: chapter.duration_ms,
            metadata: chapter.metadata
          }
        end

        def serialize_review(review)
          {
            id: review.id,
            review_id: review.review_id,
            status: review.status,
            review_mode: review.review_mode,
            quality_score: review.quality_score,
            findings: review.findings,
            completeness_checks: review.completeness_checks,
            approval_notes: review.approval_notes,
            rejection_reason: review.rejection_reason,
            revision_count: review.revision_count,
            review_duration_ms: review.review_duration_ms,
            reviewer_role_id: review.reviewer_role_id,
            reviewer_agent_id: review.reviewer_agent_id,
            team_task_id: review.team_task_id,
            created_at: review.created_at
          }
        end
      end
    end
  end
end
