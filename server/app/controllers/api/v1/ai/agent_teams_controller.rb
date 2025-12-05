# frozen_string_literal: true

module Api
  module V1
    module Ai
      # AiAgentTeamsController - Manages AI agent team CRUD operations and execution
      # Provides RESTful API for CrewAI-style team orchestration
      class AgentTeamsController < ApplicationController
        include AuditLogging

        # Disable parameter wrapping entirely to avoid conflicts
        wrap_parameters false

        before_action :authenticate_request
        before_action :set_team, only: %i[show update destroy execute execute_complete execute_failed add_member remove_member]
        before_action :authorize_teams_access!, except: %i[execute_complete execute_failed]
        before_action :authorize_team_execution!, only: [:execute]

        # GET /api/v1/ai/agent_teams
        def index
          @teams = current_account.ai_agent_teams
                                  .includes(:ai_agent_team_members)
                                  .order(created_at: :desc)

          # Filter by status if provided
          @teams = @teams.where(status: params[:status]) if params[:status].present?

          # Filter by team type if provided
          @teams = @teams.where(team_type: params[:team_type]) if params[:team_type].present?

          render_success(
            @teams.map { |team| serialize_team(team) },
            meta: {
              total: @teams.count,
              filters: {
                status: params[:status],
                team_type: params[:team_type]
              }
            }
          )
        end

        # GET /api/v1/ai/agent_teams/:id
        def show
          render_success(serialize_team_detail(@team))
        end

        # POST /api/v1/ai/agent_teams
        def create
          @team = current_account.ai_agent_teams.build(team_params)

          if @team.save
            log_audit_event('ai_agent_team.created', @team, metadata: { team_name: @team.name })

            render_success(serialize_team_detail(@team), status: :created)
          else
            render_validation_error(@team.errors)
          end
        end

        # PATCH/PUT /api/v1/ai/agent_teams/:id
        def update
          if @team.update(team_params)
            changes = @team.saved_changes.keys
            log_audit_event('ai_agent_team.updated', @team, metadata: { changes: changes })

            render_success(serialize_team_detail(@team))
          else
            render_validation_error(@team.errors)
          end
        end

        # DELETE /api/v1/ai/agent_teams/:id
        def destroy
          team_name = @team.name

          if @team.destroy
            log_audit_event('ai_agent_team.deleted', @team, metadata: { team_name: team_name })

            render_success({ message: 'Team deleted successfully' })
          else
            render_error('Failed to delete team', status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agent_teams/:id/members
        def add_member
          agent = current_account.ai_agents.find(params[:agent_id])
          member = @team.add_member(
            agent: agent,
            role: params[:role],
            capabilities: params[:capabilities] || [],
            priority_order: params[:priority_order],
            is_lead: params[:is_lead] || false
          )

          log_audit_event('ai_agent_team.member_added', member, metadata: { agent_id: agent.id, role: params[:role] })

          render_success(serialize_member(member))
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        rescue ActiveRecord::RecordNotFound
          render_not_found('Agent')
        end

        # DELETE /api/v1/ai/agent_teams/:id/members/:member_id
        def remove_member
          member = @team.ai_agent_team_members.find(params[:member_id])
          agent_name = member.ai_agent_name

          if member.destroy
            log_audit_event('ai_agent_team.member_removed', member, metadata: { agent_name: agent_name })

            render_success({ message: 'Member removed successfully' })
          else
            render_error('Failed to remove member', status: :unprocessable_content)
          end
        rescue ActiveRecord::RecordNotFound
          render_not_found('Member')
        end

        # POST /api/v1/ai/agent_teams/:id/execute
        def execute
          # Queue team execution job
          job = AiAgentTeamExecutionJob.perform_async(
            team_id: @team.id,
            user_id: current_user.id,
            input: params[:input] || {},
            context: params[:context] || {}
          )

          log_audit_event('ai_agent_team.execution_started', @team,
            metadata: { job_id: job })

          render_success({
            team_id: @team.id,
            job_id: job,
            status: 'queued'
          })
        rescue StandardError => e
          render_error("Failed to execute team: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/agent_teams/:id/execution_complete (internal - called by worker)
        def execute_complete
          # Store execution results (would typically update a TeamExecution record)
          log_audit_event('ai_agent_team.execution_completed', @team,
            metadata: { job_id: params[:job_id], completed_at: params[:completed_at] })

          render_success({ message: 'Execution completed recorded' })
        end

        # POST /api/v1/ai/agent_teams/:id/execution_failed (internal - called by worker)
        def execute_failed
          # Store execution failure (would typically update a TeamExecution record)
          log_audit_event('ai_agent_team.execution_failed', @team,
            metadata: { job_id: params[:job_id], error: params[:error], failed_at: params[:failed_at] })

          render_success({ message: 'Execution failure recorded' })
        end

        private

        def set_team
          @team = current_account.ai_agent_teams.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found('Team') and return false
        end

        def authorize_teams_access!
          return if current_user.has_permission?('ai.teams.manage')

          render_forbidden
        end

        def authorize_team_execution!
          return if current_user.has_permission?('ai.teams.execute')

          render_forbidden
        end

        def team_params
          params.permit(
            :name,
            :description,
            :team_type,
            :coordination_strategy,
            :status,
            team_config: {}
          )
        end

        def serialize_team(team)
          {
            id: team.id,
            name: team.name,
            description: team.description,
            team_type: team.team_type,
            coordination_strategy: team.coordination_strategy,
            status: team.status,
            member_count: team.ai_agent_team_members.count,
            has_lead: team.has_lead?,
            created_at: team.created_at,
            updated_at: team.updated_at
          }
        end

        def serialize_team_detail(team)
          serialize_team(team).merge(
            team_config: team.team_config,
            members: team.ai_agent_team_members.order(:priority_order).map { |m| serialize_member(m) },
            stats: team.team_stats
          )
        end

        def serialize_member(member)
          {
            id: member.id,
            agent_id: member.ai_agent_id,
            agent_name: member.ai_agent_name,
            role: member.role,
            capabilities: member.capabilities,
            priority_order: member.priority_order,
            is_lead: member.is_lead,
            created_at: member.created_at
          }
        end
      end
    end
  end
end
