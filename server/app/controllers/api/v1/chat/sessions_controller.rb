# frozen_string_literal: true

module Api
  module V1
    module Chat
      class SessionsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_session, only: %i[show update destroy transfer close messages send_message]

        # GET /api/v1/chat/sessions
        def index
          scope = current_user.account.chat_sessions

          # Apply filters
          scope = scope.where(channel_id: params[:channel_id]) if params[:channel_id].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(assigned_agent_id: params[:agent_id]) if params[:agent_id].present?
          scope = scope.active if params[:active] == "true"

          # Search by platform user ID
          if params[:platform_user_id].present?
            scope = scope.where(platform_user_id: params[:platform_user_id])
          end

          # Date range
          if params[:since].present?
            scope = scope.where("created_at >= ?", Time.zone.parse(params[:since]))
          end

          # Sorting and pagination
          scope = scope.order(last_activity_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:session_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("chat.sessions.list", current_user.account)
        end

        # GET /api/v1/chat/sessions/:id
        def show
          render_success(session: @session.session_details)
          log_audit_event("chat.sessions.read", @session)
        end

        # PATCH/PUT /api/v1/chat/sessions/:id
        def update
          if @session.update(session_params)
            render_success(session: @session.session_details)
            log_audit_event("chat.sessions.update", @session)
          else
            render_error(@session.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/chat/sessions/:id
        def destroy
          @session.destroy!
          render_success(message: "Session deleted successfully")
          log_audit_event("chat.sessions.delete", @session)
        end

        # POST /api/v1/chat/sessions/:id/transfer
        def transfer
          new_agent_id = params[:agent_id]

          unless new_agent_id.present?
            render_error("agent_id is required", status: :unprocessable_entity)
            return
          end

          # Verify agent exists and is accessible
          agent = current_user.account.ai_agents.find_by(id: new_agent_id)
          unless agent
            render_error("Agent not found", status: :not_found)
            return
          end

          @session.update!(assigned_agent_id: new_agent_id)
          render_success(
            session: @session.session_details,
            message: "Session transferred to #{agent.name}"
          )
          log_audit_event("chat.sessions.transfer", @session, { new_agent_id: new_agent_id })
        end

        # POST /api/v1/chat/sessions/:id/close
        def close
          @session.close!(reason: params[:reason])
          render_success(session: @session.session_details)
          log_audit_event("chat.sessions.close", @session)
        end

        # GET /api/v1/chat/sessions/:id/messages
        def messages
          scope = @session.messages

          # Filters
          scope = scope.where(direction: params[:direction]) if params[:direction].present?
          scope = scope.where(message_type: params[:type]) if params[:type].present?

          # Date range
          if params[:since].present?
            scope = scope.where("created_at >= ?", Time.zone.parse(params[:since]))
          end

          # Sorting and pagination
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:message_summary),
            pagination: pagination_data(scope)
          )
        end

        # POST /api/v1/chat/sessions/:id/messages
        def send_message
          unless params[:content].present?
            render_error("content is required", status: :unprocessable_entity)
            return
          end

          adapter = ::Chat::GatewayService.adapter_for(@session.channel)
          result = adapter.send_message(
            @session.channel,
            @session.platform_user_id,
            params[:content],
            message_type: params[:message_type] || "text"
          )

          if result[:success]
            # Record the outbound message
            message = @session.messages.create!(
              direction: "outbound",
              message_type: params[:message_type] || "text",
              content: params[:content],
              sanitized_content: params[:content],
              delivery_status: "sent",
              platform_metadata: result[:metadata] || {}
            )

            render_success(message: message.message_summary)
            log_audit_event("chat.sessions.send_message", @session)
          else
            render_error(result[:error], status: :unprocessable_entity)
          end
        end

        # GET /api/v1/chat/sessions/active
        def active
          scope = current_user.account.chat_sessions.active.includes(:channel, :assigned_agent)

          # Group by channel if requested
          if params[:group_by_channel] == "true"
            grouped = scope.group_by(&:channel_id).transform_values do |sessions|
              sessions.map(&:session_summary)
            end
            render_success(sessions_by_channel: grouped)
          else
            scope = scope.order(last_activity_at: :desc).limit(params[:limit]&.to_i || 50)
            render_success(items: scope.map(&:session_summary))
          end
        end

        # GET /api/v1/chat/sessions/stats
        def stats
          account = current_user.account
          sessions = account.chat_sessions

          render_success(
            stats: {
              total: sessions.count,
              active: sessions.active.count,
              closed: sessions.closed.count,
              avg_duration_minutes: sessions.closed.average("EXTRACT(EPOCH FROM (chat_sessions.updated_at - chat_sessions.created_at)) / 60")&.round(2),
              avg_messages_per_session: sessions.joins(:messages).group("chat_sessions.id").count.values.then { |v| v.any? ? (v.sum.to_f / v.count).round(2) : 0 },
              by_platform: sessions.joins(:channel).group("chat_channels.platform").count,
              by_status: sessions.group("chat_sessions.status").count
            }
          )
        end

        private

        def set_session
          @session = current_user.account.chat_sessions.find(params[:id])
        end

        def session_params
          params.require(:session).permit(
            :assigned_agent_id,
            :status,
            context_window: {}
          )
        end
      end
    end
  end
end
