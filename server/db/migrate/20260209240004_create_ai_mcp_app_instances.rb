# frozen_string_literal: true

class CreateAiMcpAppInstances < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_mcp_app_instances, id: :uuid do |t|
      t.references :mcp_app, type: :uuid, null: false, foreign_key: { to_table: :ai_mcp_apps }, index: true
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :session, type: :uuid, foreign_key: { to_table: :ai_agui_sessions }, index: true
      t.string :status, null: false, default: "created"
      t.jsonb :state, default: {}
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
  end
end
