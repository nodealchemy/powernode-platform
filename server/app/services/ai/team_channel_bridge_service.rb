# frozen_string_literal: true

module Ai
  class TeamChannelBridgeService
    # Called after Chat::Message create when session's channel is bridged.
    # Creates a TeamMessage(type: human_input) on the linked team channel.
    def sync_inbound_to_team_channel(chat_message)
      session = chat_message.session
      channel = session.channel
      return unless channel.bridged?

      team_channel = channel.team_channel
      return unless team_channel

      Ai::TeamMessage.create!(
        channel: team_channel,
        content: chat_message.content_for_ai,
        message_type: "human_input",
        priority: "normal",
        metadata: {
          source: "chat_bridge",
          chat_message_id: chat_message.id,
          chat_channel_id: channel.id,
          platform: channel.platform,
          platform_user: session.platform_username
        }
      )
    rescue StandardError => e
      Rails.logger.error "[TeamChannelBridge] Inbound sync failed: #{e.message}"
    end

    # Called after TeamMessage create when channel has bridged Chat::Channels.
    # Forwards via Chat::MessageRouter to each linked platform.
    # Skips if the message originated FROM a platform (prevents echo loop).
    def sync_outbound_to_platform(team_message)
      channel = team_message.channel
      return unless channel.present?

      bridged_chat_channels = channel.chat_channels.where(bridge_enabled: true)
        .where(bridge_direction: %w[outbound_only bidirectional])
      return if bridged_chat_channels.empty?

      # Skip messages that originated from a chat bridge
      source = team_message.metadata&.dig("source")
      source_channel_id = team_message.metadata&.dig("chat_channel_id")

      bridged_chat_channels.find_each do |chat_channel|
        # Skip the originating platform to prevent echo
        next if source == "chat_bridge" && source_channel_id == chat_channel.id

        forward_to_platform(chat_channel, team_message)
      end
    end

    private

    def forward_to_platform(chat_channel, team_message)
      # Find or create a system session for broadcasting
      session = chat_channel.sessions.find_or_create_by!(
        platform_user_id: "system_bridge"
      ) do |s|
        s.platform_username = "Team Bridge"
        s.assigned_agent = chat_channel.default_agent
      end

      sender = team_message.from_role&.role_name || team_message.user&.name || "System"
      content = "[#{sender}] #{team_message.content}"

      router = Chat::MessageRouter.new(chat_channel)
      router.route_outbound(
        session: session,
        content: content,
        message_type: "text"
      )
    rescue StandardError => e
      Rails.logger.error "[TeamChannelBridge] Outbound sync to #{chat_channel.platform}/#{chat_channel.id} failed: #{e.message}"
    end
  end
end
