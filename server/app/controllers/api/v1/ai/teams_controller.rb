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
          show update destroy analytics composition_health update_review_config
        ]

        # ============================================================================
        # TEAMS
        # ============================================================================

        # GET /api/v1/ai/teams
        def index
          teams = @crud_service.list_teams(filter_params)

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
                   @crud_service.create_team_from_template(params[:template_id], name: params[:name], user: current_user)
          else
                   @crud_service.create_team(team_params, user: current_user)
          end
          render_success(serialize_team(team), status: :created)
        end

        # PATCH /api/v1/ai/teams/:id
        def update
          team = @crud_service.update_team(@team.id, team_params)
          render_success(serialize_team(team))
        end

        # DELETE /api/v1/ai/teams/:id
        def destroy
          @crud_service.delete_team(@team.id)
          render_success(success: true)
        end

        # ============================================================================
        # ANALYTICS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/analytics
        def analytics
          period_days = params[:period_days]&.to_i || 30
          analytics = @analytics_service.get_team_analytics(@team.id, period_days: period_days)
          render_success(analytics)
        end

        # ============================================================================
        # COMPOSITION HEALTH
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/composition_health
        def composition_health
          health = @crud_service.composition_health(@team.id)
          render_success(health)
        end

        # ============================================================================
        # REVIEW CONFIG
        # ============================================================================

        # PUT /api/v1/ai/teams/:team_id/review_config
        def update_review_config
          team = @crud_service.configure_team_review(@team.id, review_config_params.to_h)
          render_success(serialize_team(team, detailed: true))
        end

        private

        def set_team_service
          @crud_service = ::Ai::Teams::CrudService.new(account: current_account)
          @analytics_service = ::Ai::Teams::AnalyticsService.new(account: current_account)
        end

        def set_team
          @team = @crud_service.get_team(params[:team_id] || params[:id])
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
      end
    end
  end
end
