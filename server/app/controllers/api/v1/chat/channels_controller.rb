# frozen_string_literal: true

module Api
  module V1
    module Chat
      class ChannelsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_channel, only: %i[show update destroy connect disconnect test regenerate_token sessions metrics]

        # GET /api/v1/chat/channels
        def index
          scope = current_user.account.chat_channels

          # Apply filters
          scope = scope.where(platform: params[:platform]) if params[:platform].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.active if params[:active] == "true"

          # Sorting and pagination
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:channel_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("chat.channels.list", current_user.account)
        end

        # GET /api/v1/chat/channels/:id
        def show
          render_success(channel: @channel.channel_details)
          log_audit_event("chat.channels.read", @channel)
        end

        # POST /api/v1/chat/channels
        def create
          channel = current_user.account.chat_channels.build(channel_params)
          channel.status ||= "disconnected"

          if channel.save
            render_success({ channel: channel.channel_details }, status: :created)
            log_audit_event("chat.channels.create", channel)
          else
            render_error(channel.errors.full_messages, status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/chat/channels/:id
        def update
          if @channel.update(channel_params)
            render_success(channel: @channel.channel_details)
            log_audit_event("chat.channels.update", @channel)
          else
            render_error(@channel.errors.full_messages, status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/chat/channels/:id
        def destroy
          @channel.destroy!
          render_success(message: "Channel deleted successfully")
          log_audit_event("chat.channels.delete", @channel)
        end

        # POST /api/v1/chat/channels/:id/connect
        def connect
          result = ::Chat::GatewayService.new(@channel).connect

          if result
            render_success(channel: @channel.reload.channel_details)
            log_audit_event("chat.channels.connect", @channel)
          else
            render_error("Failed to connect channel", status: :unprocessable_content)
          end
        end

        # POST /api/v1/chat/channels/:id/disconnect
        def disconnect
          @channel.disconnect!
          render_success(channel: @channel.channel_details)
          log_audit_event("chat.channels.disconnect", @channel)
        end

        # POST /api/v1/chat/channels/:id/test
        def test
          adapter = ::Chat::GatewayService.adapter_for(@channel)
          result = adapter.test_connection(@channel)

          if result[:success]
            render_success(
              message: "Connection test successful",
              details: result[:details]
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/chat/channels/:id/regenerate_token
        def regenerate_token
          @channel.regenerate_webhook_token!
          render_success(
            channel: @channel.channel_details,
            webhook_url: @channel.webhook_url
          )
          log_audit_event("chat.channels.regenerate_token", @channel)
        end

        # GET /api/v1/chat/channels/:id/sessions
        def sessions
          scope = @channel.sessions

          # Apply filters
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.active if params[:active] == "true"

          # Sorting and pagination
          scope = scope.order(last_activity_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:session_summary),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/chat/channels/:id/metrics
        def metrics
          sessions = @channel.sessions
          messages = @channel.messages

          # Basic counts
          total_sessions = sessions.count
          active_sessions = sessions.active.count
          total_messages = messages.count
          messages_today = messages.where("chat_messages.created_at >= ?", Time.current.beginning_of_day).count

          # Response time: average time between inbound and next outbound message in same session
          avg_response_time_result = ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array([
              <<~SQL,
                SELECT AVG(response_time_ms) as avg_response_time
                FROM (
                  SELECT EXTRACT(EPOCH FROM (outbound.created_at - inbound.created_at)) * 1000 AS response_time_ms
                  FROM chat_messages inbound
                  JOIN chat_messages outbound ON outbound.session_id = inbound.session_id
                    AND outbound.direction = 'outbound'
                    AND outbound.created_at > inbound.created_at
                    AND outbound.created_at = (
                      SELECT MIN(o2.created_at)
                      FROM chat_messages o2
                      WHERE o2.session_id = inbound.session_id
                        AND o2.direction = 'outbound'
                        AND o2.created_at > inbound.created_at
                    )
                  WHERE inbound.direction = 'inbound'
                    AND inbound.session_id IN (SELECT id FROM chat_sessions WHERE channel_id = ?)
                ) response_times
              SQL
              @channel.id
            ])
          )
          avg_response_time_ms = avg_response_time_result.first&.dig("avg_response_time")&.to_f&.round(2)

          # Resolution rate: closed sessions / total sessions
          closed_sessions = sessions.closed.count
          resolution_rate = total_sessions > 0 ? (closed_sessions.to_f / total_sessions * 100).round(2) : 0.0

          # Messages per hour (last 24h)
          messages_last_24h = messages.where("chat_messages.created_at >= ?", 24.hours.ago).count
          messages_per_hour = (messages_last_24h / 24.0).round(2)

          # Average session duration (closed sessions only)
          avg_duration_result = sessions.closed
            .where.not(closed_at: nil)
            .average("EXTRACT(EPOCH FROM (closed_at - chat_sessions.created_at)) * 1000")
          avg_session_duration_ms = avg_duration_result&.to_f&.round(2)

          # Error rate: failed messages / total outbound messages
          outbound_count = messages.outbound.count
          failed_count = messages.failed.count
          error_rate = outbound_count > 0 ? (failed_count.to_f / outbound_count * 100).round(2) : 0.0

          # Last message
          last_message_at = messages.maximum(:created_at)

          render_success(
            metrics: {
              total_sessions: total_sessions,
              active_sessions: active_sessions,
              total_messages: total_messages,
              messages_today: messages_today,
              avg_response_time_ms: avg_response_time_ms,
              resolution_rate: resolution_rate,
              messages_per_hour: messages_per_hour,
              avg_session_duration_ms: avg_session_duration_ms,
              error_rate: error_rate,
              last_message_at: last_message_at,
              status: @channel.status
            }
          )
        end

        # POST /api/v1/chat/channels/cleanup_sessions
        def cleanup_sessions
          channels_processed = 0
          total_idled = 0
          total_closed = 0

          current_user.account.chat_channels.find_each do |channel|
            manager = ::Chat::SessionManager.new(channel)
            result = manager.cleanup_stale_sessions
            total_idled += result[:idled]
            total_closed += result[:closed]
            channels_processed += 1
          end

          render_success(
            channels_processed: channels_processed,
            total_idled: total_idled,
            total_closed: total_closed
          )
        end

        # GET /api/v1/chat/channels/platforms
        def platforms
          render_success(
            platforms: ::Chat::Channel::PLATFORMS.map do |platform|
              {
                id: platform,
                name: platform.titleize,
                supported: true,
                webhook_required: %w[telegram discord slack whatsapp].include?(platform),
                oauth_required: %w[slack].include?(platform)
              }
            end
          )
        end

        private

        def set_channel
          @channel = current_user.account.chat_channels.find(params[:id])
        end

        def channel_params
          permitted = params.require(:channel).permit(
            :name,
            :platform,
            :default_agent_id,
            :rate_limit_per_minute,
            :auto_respond,
            :welcome_message,
            :session_timeout_minutes,
            configuration: {}
          )

          # Merge routing_config and agent_personality into configuration JSON
          config = permitted[:configuration] || @channel&.configuration || {}
          if params[:channel][:routing_config].present?
            config = config.merge("routing_config" => params[:channel][:routing_config].to_unsafe_h)
          end
          if params[:channel][:agent_personality].present?
            config = config.merge("agent_personality" => params[:channel][:agent_personality].to_unsafe_h)
          end
          permitted[:configuration] = config if params[:channel][:routing_config].present? || params[:channel][:agent_personality].present?

          permitted
        end
      end
    end
  end
end
