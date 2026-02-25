# frozen_string_literal: true

class AddTeamChannelLinkToChatChannels < ActiveRecord::Migration[8.0]
  def change
    add_reference :chat_channels, :ai_team_channel, type: :uuid,
                  foreign_key: { to_table: :ai_team_channels }, null: true
    add_column :chat_channels, :bridge_enabled, :boolean, default: false
    add_column :chat_channels, :bridge_direction, :string, default: "bidirectional"
  end
end
