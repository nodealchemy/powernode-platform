# frozen_string_literal: true

class CreateDevopsAiConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :devops_ai_configs, id: :uuid do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, type: :uuid

      t.string :name, null: false, limit: 255
      t.text :description
      t.string :config_type, null: false, limit: 50
      t.string :provider, null: false, limit: 50
      t.string :model, null: false, limit: 100
      t.string :status, null: false, default: 'active', limit: 20

      # Model parameters
      t.integer :max_tokens, default: 4096
      t.decimal :temperature, precision: 3, scale: 2, default: 0.7
      t.decimal :top_p, precision: 3, scale: 2, default: 1.0
      t.decimal :frequency_penalty, precision: 3, scale: 2, default: 0.0
      t.decimal :presence_penalty, precision: 3, scale: 2, default: 0.0
      t.integer :timeout_seconds, default: 30

      # Configuration JSON columns
      t.jsonb :system_prompt, null: false, default: {}
      t.jsonb :settings, null: false, default: {}
      t.jsonb :rate_limits, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      # Usage tracking
      t.integer :total_requests, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0
      t.datetime :last_used_at

      # Flags
      t.boolean :is_default, null: false, default: false
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :devops_ai_configs, [:account_id, :name], unique: true
    add_index :devops_ai_configs, [:account_id, :config_type]
    add_index :devops_ai_configs, [:account_id, :is_default], where: "(is_default = true)"
    add_index :devops_ai_configs, :status
    add_index :devops_ai_configs, :provider

    add_check_constraint :devops_ai_configs,
      "status IN ('active', 'inactive', 'archived')",
      name: "check_devops_ai_config_status"

    add_check_constraint :devops_ai_configs,
      "config_type IN ('chat', 'completion', 'embedding', 'code_review', 'code_generation', 'custom')",
      name: "check_devops_ai_config_type"
  end
end
