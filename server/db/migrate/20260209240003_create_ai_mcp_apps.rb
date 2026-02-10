# frozen_string_literal: true

class CreateAiMcpApps < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_mcp_apps, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.string :app_type, null: false, default: "custom"
      t.string :status, null: false, default: "draft"
      t.text :html_content
      t.jsonb :csp_policy, default: {}
      t.jsonb :sandbox_config, default: {}
      t.jsonb :input_schema, default: {}
      t.jsonb :output_schema, default: {}
      t.jsonb :metadata, default: {}
      t.string :version, default: "1.0.0"
      t.uuid :created_by_id
      t.timestamps
    end

    add_index :ai_mcp_apps, [:account_id, :name], unique: true
  end
end
