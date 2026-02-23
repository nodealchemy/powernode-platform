# frozen_string_literal: true

module Api
  module V1
    module Ai
      class WorkspacesController < ApplicationController
        before_action :authorize_ai_conversations

        # GET /api/v1/ai/workspaces
        def index
          workspaces = workspace_service.list_workspaces

          render_success(
            workspaces: workspaces.map { |c| serialize_workspace(c) }
          )
        end

        # POST /api/v1/ai/workspaces
        def create
          result = workspace_service.create_workspace(
            name: params.require(:name),
            agent_ids: Array(params[:agent_ids])
          )

          primary_agent = result[:conversation].agent
          render_success(
            workspace: serialize_workspace(result[:conversation]),
            team: { id: result[:team].id, name: result[:team].name },
            primary_agent: primary_agent ? { id: primary_agent.id, name: primary_agent.name } : nil
          )
        rescue ActionController::ParameterMissing => e
          render_error(e.message, :unprocessable_entity)
        rescue StandardError => e
          render_error("Failed to create workspace: #{e.message}", :unprocessable_entity)
        end

        # GET /api/v1/ai/workspaces/:id
        def show
          conversation = find_workspace_conversation!
          team = conversation.agent_team

          render_success(
            workspace: serialize_workspace(conversation),
            members: team.members.includes(:agent).map { |m|
              {
                id: m.ai_agent_id,
                name: m.agent_name,
                role: m.role,
                agent_type: m.agent_agent_type,
                is_lead: m.is_lead,
                is_concierge: m.agent.is_concierge?
              }
            }
          )
        end

        # GET /api/v1/ai/workspaces/active_sessions
        def active_sessions
          sessions = workspace_service.active_mcp_sessions

          render_success(
            sessions: sessions.map { |s| serialize_session(s) }
          )
        end

        # POST /api/v1/ai/workspaces/:id/invite
        def invite
          conversation = find_workspace_conversation!
          agent = resolve_agent(params.require(:agent_id))
          return render_error("Agent not found", :not_found) unless agent

          workspace_service.invite_agent(workspace_conversation: conversation, agent: agent)

          render_success(
            message: "#{agent.name} invited to workspace",
            agent: { id: agent.id, name: agent.name, agent_type: agent.agent_type }
          )
        rescue ArgumentError => e
          render_error(e.message, :unprocessable_entity)
        end

        # DELETE /api/v1/ai/workspaces/:id/members/:agent_id
        def remove_member
          conversation = find_workspace_conversation!
          agent = current_account.ai_agents.find_by(id: params[:agent_id])
          return render_error("Agent not found", :not_found) unless agent

          workspace_service.remove_agent(workspace_conversation: conversation, agent: agent)

          render_success(message: "#{agent.name} removed from workspace")
        rescue ArgumentError => e
          render_error(e.message, :unprocessable_entity)
        end

        private

        def workspace_service
          @workspace_service ||= ::Ai::WorkspaceService.new(account: current_account, user: current_user)
        end

        def authorize_ai_conversations
          unless current_user.has_permission?("ai.conversations.create")
            render_error("Permission denied", :forbidden)
          end
        end

        def find_workspace_conversation!
          conversation = ::Ai::Conversation.where(account: current_account)
            .joins(:agent_team)
            .where(ai_agent_teams: { team_type: "workspace" })
            .find_by(id: params[:id])

          conversation ||= ::Ai::Conversation.where(account: current_account)
            .joins(:agent_team)
            .where(ai_agent_teams: { team_type: "workspace" })
            .find_by(conversation_id: params[:id])

          render_error("Workspace not found", :not_found) and return unless conversation
          conversation
        end

        def resolve_agent(agent_id)
          if agent_id == "concierge"
            current_account.ai_agents.default_concierge.first
          else
            current_account.ai_agents.find_by(id: agent_id)
          end
        end

        def serialize_workspace(conversation)
          team = conversation.agent_team
          {
            id: conversation.id,
            conversation_id: conversation.conversation_id,
            title: conversation.title,
            status: conversation.status,
            team_id: team&.id,
            team_name: team&.name,
            member_count: team&.members&.count || 0,
            message_count: conversation.message_count,
            is_collaborative: conversation.is_collaborative?,
            websocket_channel: conversation.websocket_channel,
            last_activity_at: conversation.last_activity_at&.iso8601,
            created_at: conversation.created_at&.iso8601
          }
        end

        def serialize_session(session)
          {
            id: session.id,
            display_name: session.display_name || session.ai_agent&.name,
            oauth_application: session.oauth_application ? {
              id: session.oauth_application.id,
              name: session.oauth_application.name
            } : nil,
            agent: session.ai_agent ? {
              id: session.ai_agent.id,
              name: session.ai_agent.name,
              agent_type: session.ai_agent.agent_type,
              status: session.ai_agent.status
            } : nil,
            user: {
              id: session.user.id,
              name: session.user.name || session.user.email
            },
            last_activity_at: session.last_activity_at&.iso8601,
            created_at: session.created_at&.iso8601
          }
        end
      end
    end
  end
end
