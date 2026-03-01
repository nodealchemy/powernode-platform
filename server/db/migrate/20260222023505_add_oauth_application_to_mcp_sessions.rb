# frozen_string_literal: true

class AddOauthApplicationToMcpSessions < ActiveRecord::Migration[8.0]
  def change
    add_reference :mcp_sessions, :oauth_application, type: :uuid, foreign_key: { to_table: :oauth_applications }, index: true, null: true
    add_reference :mcp_sessions, :ai_agent, type: :uuid, foreign_key: { to_table: :ai_agents }, index: true, null: true
    add_column :mcp_sessions, :display_name, :string, limit: 255
  end
end
