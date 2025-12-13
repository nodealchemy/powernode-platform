# frozen_string_literal: true

class CreateMcpSystem < ActiveRecord::Migration[7.1]
  def change
    create_table :mcp_servers, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: 'disconnected'
      t.string :connection_type, null: false
      t.string :command
      t.jsonb :args, default: []
      t.jsonb :env, default: {}
      t.jsonb :capabilities, default: {}
      t.datetime :last_health_check
      t.timestamps

      t.index [ :account_id, :status ]
      t.index :status
    end

    create_table :mcp_tools, id: :uuid do |t|
      t.references :mcp_server, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.jsonb :input_schema, null: false, default: {}
      t.timestamps

      t.index [ :mcp_server_id, :name ]
    end

    create_table :mcp_tool_executions, id: :uuid do |t|
      t.references :mcp_tool, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false
      t.jsonb :parameters, default: {}
      t.jsonb :result, default: {}
      t.text :error_message
      t.integer :execution_time_ms
      t.timestamps

      t.index [ :mcp_tool_id, :created_at ]
      t.index [ :user_id, :created_at ]
    end
  end
end
