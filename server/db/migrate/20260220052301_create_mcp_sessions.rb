# frozen_string_literal: true

class CreateMcpSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_sessions, id: :uuid do |t|
      t.string :session_token, null: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.jsonb :client_info, default: {}
      t.string :protocol_version
      t.datetime :last_activity_at
      t.string :ip_address
      t.string :user_agent
      t.datetime :expires_at
      t.datetime :revoked_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :mcp_sessions, :session_token, unique: true
    add_index :mcp_sessions, [:account_id, :status]
    add_index :mcp_sessions, [:user_id, :status]
    add_index :mcp_sessions, :expires_at
  end
end
