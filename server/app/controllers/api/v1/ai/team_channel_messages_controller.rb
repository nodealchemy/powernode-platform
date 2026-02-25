# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TeamChannelMessagesController < ApplicationController
        before_action :authenticate_request
        before_action :set_team, only: %i[messages send_message link_chat_channel unlink_chat_channel]
        before_action :set_channel, only: %i[messages send_message link_chat_channel unlink_chat_channel]

        # GET /api/v1/ai/channels
        # Returns all channels across user's teams for the chat sidebar
        def my_channels
          teams = current_account.ai_agent_teams.includes(ai_team_channels: :chat_channels)
          channels = teams.flat_map do |team|
            team.ai_team_channels.map { |ch| serialize_sidebar_channel(ch, team) }
          end

          # Sort by last activity (most recent first)
          channels.sort_by! { |c| c[:last_activity_at] || "1970-01-01" }.reverse!

          render_success(channels: channels)
        end

        # GET /api/v1/ai/teams/:team_id/channels/:channel_id/messages
        def messages
          msgs = @channel.messages
            .includes(:from_role, :to_role, :user)
            .order(:sequence_number)
            .limit(params.fetch(:limit, 100).to_i)

          if params[:after].present?
            msgs = msgs.where("sequence_number > ?", params[:after].to_i)
          end

          render_success(messages: msgs.map { |m| serialize_message(m) })
        end

        # POST /api/v1/ai/teams/:team_id/channels/:channel_id/messages
        def send_message
          message = @channel.messages.create!(
            content: params.require(:content),
            message_type: "human_input",
            priority: params.fetch(:priority, "normal"),
            user: current_user
          )

          render_success(serialize_message(message), status: :created)
        end

        # POST /api/v1/ai/teams/:team_id/channels/:channel_id/link
        def link_chat_channel
          chat_channel = current_account.chat_channels.find(params.require(:chat_channel_id))
          direction = params.fetch(:direction, "bidirectional")

          unless %w[inbound_only outbound_only bidirectional].include?(direction)
            return render_error("Invalid direction. Must be: inbound_only, outbound_only, bidirectional", status: :unprocessable_entity)
          end

          chat_channel.update!(
            team_channel: @channel,
            bridge_enabled: true,
            bridge_direction: direction
          )

          render_success(
            chat_channel_id: chat_channel.id,
            platform: chat_channel.platform,
            bridge_direction: direction,
            linked: true
          )
        end

        # DELETE /api/v1/ai/teams/:team_id/channels/:channel_id/unlink
        def unlink_chat_channel
          chat_channel = current_account.chat_channels.find(params.require(:chat_channel_id))

          chat_channel.update!(
            team_channel: nil,
            bridge_enabled: false,
            bridge_direction: "bidirectional"
          )

          render_success(chat_channel_id: chat_channel.id, linked: false)
        end

        private

        def set_team
          @team = current_account.ai_agent_teams.find(params[:team_id])
        end

        def set_channel
          @channel = @team.ai_team_channels.find(params[:channel_id])
        end

        def serialize_sidebar_channel(channel, team)
          last_msg = channel.messages.order(created_at: :desc).first
          active_execution = team.team_executions.active.exists?

          {
            id: channel.id,
            name: channel.name,
            channel_type: channel.channel_type,
            description: channel.description,
            message_count: channel.message_count,
            is_persistent: channel.is_persistent,
            team: { id: team.id, name: team.name },
            has_active_execution: active_execution,
            last_activity_at: last_msg&.created_at&.iso8601,
            linked_platforms: channel.bridged_platforms
          }
        end

        def serialize_message(msg)
          {
            id: msg.id,
            content: msg.content,
            message_type: msg.message_type,
            priority: msg.priority,
            from_role: msg.from_role ? {
              id: msg.from_role.id,
              role_name: msg.from_role.role_name,
              agent_name: msg.from_role.ai_agent&.name
            } : nil,
            to_role: msg.to_role ? {
              id: msg.to_role.id,
              role_name: msg.to_role.role_name,
              agent_name: msg.to_role.ai_agent&.name
            } : nil,
            user: msg.user ? {
              id: msg.user.id,
              name: msg.user.name,
              email: msg.user.email
            } : nil,
            requires_response: msg.requires_response,
            responded_at: msg.responded_at,
            sequence_number: msg.sequence_number,
            created_at: msg.created_at
          }
        end
      end
    end
  end
end
