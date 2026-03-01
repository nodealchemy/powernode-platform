# frozen_string_literal: true

class CreateAiMissions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_missions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, index: true
      t.references :created_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :repository, type: :uuid, foreign_key: { to_table: :git_repositories }, index: true
      t.references :team, type: :uuid, foreign_key: { to_table: :ai_agent_teams }
      t.references :conversation, type: :uuid, foreign_key: { to_table: :ai_conversations }
      t.references :risk_contract, type: :uuid, foreign_key: { to_table: :ai_code_factory_risk_contracts }
      t.references :ralph_loop, type: :uuid, foreign_key: { to_table: :ai_ralph_loops }
      t.references :review_state, type: :uuid, foreign_key: { to_table: :ai_code_factory_review_states }

      t.string :name, null: false
      t.text :description
      t.string :mission_type, null: false
      t.string :status, null: false, default: "draft"
      t.text :objective
      t.string :current_phase

      t.jsonb :phase_config, default: {}
      t.jsonb :analysis_result, default: {}
      t.jsonb :feature_suggestions, default: []
      t.jsonb :selected_feature, default: {}
      t.jsonb :prd_json, default: {}
      t.jsonb :test_result, default: {}
      t.jsonb :review_result, default: {}
      t.jsonb :phase_history, default: []
      t.jsonb :configuration, default: {}
      t.jsonb :metadata, default: {}

      t.string :branch_name
      t.string :base_branch, default: "main"
      t.integer :pr_number
      t.string :pr_url

      t.integer :deployed_port
      t.string :deployed_url
      t.string :deployed_container_id

      t.text :error_message
      t.jsonb :error_details, default: {}

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      t.timestamps
    end

    add_index :ai_missions, [:account_id, :status]
    add_index :ai_missions, [:account_id, :mission_type]
    add_index :ai_missions, :deployed_port, where: "status = 'active' AND deployed_port IS NOT NULL", unique: true
  end
end
