# frozen_string_literal: true

class DropDeprecatedCicdTables < ActiveRecord::Migration[8.0]
  def up
    # Remove the old foreign key from pipeline_steps if it exists
    if foreign_key_exists?(:ci_cd_pipeline_steps, :ci_cd_prompt_templates)
      remove_foreign_key :ci_cd_pipeline_steps, :ci_cd_prompt_templates
    end

    # Remove old column from pipeline_steps
    if column_exists?(:ci_cd_pipeline_steps, :ci_cd_prompt_template_id)
      remove_column :ci_cd_pipeline_steps, :ci_cd_prompt_template_id
    end

    # Remove foreign key from pipelines to ai_configs before dropping table
    if foreign_key_exists?(:ci_cd_pipelines, :ci_cd_ai_configs)
      remove_foreign_key :ci_cd_pipelines, :ci_cd_ai_configs
    end

    # Remove the ai_config column from pipelines (deprecated - use shared AI providers)
    if column_exists?(:ci_cd_pipelines, :ci_cd_ai_config_id)
      remove_column :ci_cd_pipelines, :ci_cd_ai_config_id
    end

    # Drop deprecated tables
    drop_table :ci_cd_prompt_templates if table_exists?(:ci_cd_prompt_templates)
    drop_table :ci_cd_ai_configs if table_exists?(:ci_cd_ai_configs)
  end

  def down
    # Recreate ci_cd_ai_configs
    create_table :ci_cd_ai_configs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :created_by_id
      t.string :name, null: false
      t.string :provider_type, null: false
      t.string :model_id, null: false
      t.integer :max_tokens, default: 16000
      t.integer :max_thinking_tokens, default: 8000
      t.float :temperature, default: 0.7
      t.integer :timeout_seconds, default: 300
      t.string :credential_key
      t.jsonb :configuration, default: {}
      t.integer :priority, default: 0
      t.boolean :is_active, default: true
      t.boolean :is_default, default: false
      t.timestamps
    end

    add_foreign_key :ci_cd_ai_configs, :accounts, on_delete: :cascade

    # Recreate ci_cd_prompt_templates
    create_table :ci_cd_prompt_templates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :created_by_id
      t.string :name, null: false
      t.string :slug, null: false
      t.string :category, null: false
      t.text :description
      t.text :content, null: false
      t.jsonb :variables, default: []
      t.jsonb :metadata, default: {}
      t.integer :version, default: 1
      t.uuid :parent_template_id
      t.boolean :is_active, default: true
      t.boolean :is_system, default: false
      t.timestamps
    end

    add_foreign_key :ci_cd_prompt_templates, :accounts, on_delete: :cascade

    # Re-add column to pipeline_steps
    add_column :ci_cd_pipeline_steps, :ci_cd_prompt_template_id, :uuid
    add_foreign_key :ci_cd_pipeline_steps, :ci_cd_prompt_templates, on_delete: :nullify
  end
end
