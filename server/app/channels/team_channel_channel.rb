# frozen_string_literal: true

# TeamChannelChannel - Real-time team channel message streaming
#
# Subscribes to new messages on a specific Ai::TeamChannel.
# Events: message_created
#
class TeamChannelChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user
    return reject unless params[:channel_id]

    @channel = Ai::TeamChannel.find_by(id: params[:channel_id])
    return reject unless @channel

    # Verify user has access to this team via account
    team = @channel.agent_team
    return reject unless team && team.account_id == current_user.account_id

    stream_from "team_channel:#{@channel.id}"

    transmit({
      type: "subscription.confirmed",
      channel: "team_channel",
      channel_id: @channel.id,
      timestamp: Time.current.iso8601
    })
  end

  def unsubscribed
    Rails.logger.info "[TeamChannelChannel] User #{current_user&.id} unsubscribed from channel #{@channel&.id}"
  end
end
