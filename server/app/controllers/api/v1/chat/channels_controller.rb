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
          channel.created_by = current_user

          if channel.save
            render_success({ channel: channel.channel_details }, status: :created)
            log_audit_event("chat.channels.create", channel)
          else
            render_error(channel.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/chat/channels/:id
        def update
          if @channel.update(channel_params)
            render_success(channel: @channel.channel_details)
            log_audit_event("chat.channels.update", @channel)
          else
            render_error(@channel.errors.full_messages, status: :unprocessable_entity)
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
          result = ::Chat::GatewayService.new(account: current_user.account).connect_channel(@channel)

          if result[:success]
            render_success(channel: @channel.reload.channel_details)
            log_audit_event("chat.channels.connect", @channel)
          else
            render_error(result[:error], status: :unprocessable_entity)
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
            render_error(result[:error], status: :unprocessable_entity)
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
          render_success(
            metrics: {
              total_sessions: @channel.sessions.count,
              active_sessions: @channel.sessions.active.count,
              total_messages: @channel.messages.count,
              messages_today: @channel.messages.where("created_at >= ?", Time.current.beginning_of_day).count,
              avg_response_time_ms: @channel.sessions.average(:avg_response_time_ms)&.round(2),
              status: @channel.status
            }
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
          params.require(:channel).permit(
            :name,
            :platform,
            :default_agent_id,
            :rate_limit_per_minute,
            :auto_respond,
            :welcome_message,
            :session_timeout_minutes,
            configuration: {}
          )
        end
      end
    end
  end
end
