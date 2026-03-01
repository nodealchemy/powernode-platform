# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TeamRolesChannelsController < ApplicationController
        rescue_from ::Ai::TeamAuthorityService::AuthorityViolation do |e|
          render_error(e.message, status: :forbidden)
        end

        before_action :authenticate_request
        before_action :set_team_service
        before_action :set_team, only: %i[
          list_roles create_role update_role delete_role assign_agent_to_role apply_role_profile
          list_channels create_channel show_channel update_channel delete_channel
        ]

        # ============================================================================
        # ROLES
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/roles
        def list_roles
          roles = @config_service.list_roles(@team.id)
          render_success(roles: roles.map { |r| serialize_role(r) })
        end

        # POST /api/v1/ai/teams/:team_id/roles
        def create_role
          role = @config_service.create_role(@team.id, role_params)
          render_success(serialize_role(role), status: :created)
        end

        # PATCH /api/v1/ai/teams/:team_id/roles/:id
        def update_role
          role = @config_service.update_role(@team.id, params[:id], role_params)
          render_success(serialize_role(role))
        end

        # DELETE /api/v1/ai/teams/:team_id/roles/:id
        def delete_role
          @config_service.delete_role(@team.id, params[:id])
          render_success(success: true)
        end

        # POST /api/v1/ai/teams/:team_id/roles/:id/assign_agent
        def assign_agent_to_role
          role = @config_service.assign_agent_to_role(@team.id, params[:id], params[:agent_id])
          render_success(serialize_role(role))
        end

        # POST /api/v1/ai/teams/:team_id/roles/:id/apply_profile
        def apply_role_profile
          role = @crud_service.apply_role_profile(@team.id, params[:id], params[:profile_id])
          render_success(serialize_role(role))
        end

        # ============================================================================
        # CHANNELS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/channels
        def list_channels
          channels = @config_service.list_channels(@team.id)
          render_success(channels: channels.map { |c| serialize_channel(c) })
        end

        # POST /api/v1/ai/teams/:team_id/channels
        def create_channel
          channel = @config_service.create_channel(@team.id, channel_params)
          render_success(serialize_channel(channel), status: :created)
        end

        # GET /api/v1/ai/teams/:team_id/channels/:id
        def show_channel
          channel = @config_service.get_channel(@team.id, params[:id])
          render_success(serialize_channel(channel))
        end

        # PATCH /api/v1/ai/teams/:team_id/channels/:id
        def update_channel
          channel = @config_service.update_channel(@team.id, params[:id], channel_params)
          render_success(serialize_channel(channel))
        end

        # DELETE /api/v1/ai/teams/:team_id/channels/:id
        def delete_channel
          @config_service.delete_channel(@team.id, params[:id])
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

        private

        def set_team_service
          @crud_service = ::Ai::Teams::CrudService.new(account: current_account)
          @config_service = ::Ai::Teams::ConfigurationService.new(account: current_account)
        end

        def set_team
          @team = @crud_service.get_team(params[:team_id] || params[:id])
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
            agent_name: role.ai_agent&.name,
            agent_type: role.ai_agent&.agent_type,
            is_lead: role.ai_agent_id.present? && role.agent_team.members.exists?(ai_agent_id: role.ai_agent_id, is_lead: true)
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
      end
    end
  end
end
