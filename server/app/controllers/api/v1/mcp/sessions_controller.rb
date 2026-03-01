# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class SessionsController < ApplicationController
        before_action :require_permission

        # GET /api/v1/mcp/sessions
        def index
          sessions = current_account.mcp_sessions
                      .includes(:user)
                      .order(last_activity_at: :desc)

          sessions = sessions.where(status: params[:status]) if params[:status].present?

          render_success(sessions.map { |s| serialize_session(s) })
        end

        # GET /api/v1/mcp/sessions/:id
        def show
          session = current_account.mcp_sessions.find(params[:id])
          render_success(serialize_session(session))
        end

        # DELETE /api/v1/mcp/sessions/:id
        def destroy
          session = current_account.mcp_sessions.find(params[:id])
          session.revoke!

          render_success({ id: session.id, status: "revoked" })
        end

        private

        def require_permission
          unless current_user.has_permission?("ai.agents.read")
            render_error("Permission denied", :forbidden)
          end
        end

        def serialize_session(session)
          {
            id: session.id,
            session_token: session.session_token,
            user_name: session.user.name,
            user_id: session.user_id,
            status: session.active? ? "active" : session.status,
            protocol_version: session.protocol_version,
            client_info: session.client_info,
            last_activity_at: session.last_activity_at&.iso8601,
            ip_address: session.ip_address,
            user_agent: session.user_agent,
            expires_at: session.expires_at&.iso8601,
            created_at: session.created_at.iso8601
          }
        end
      end
    end
  end
end
