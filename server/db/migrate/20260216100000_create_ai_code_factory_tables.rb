# frozen_string_literal: true

class CreateAiCodeFactoryTables < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_code_factory_risk_contracts, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, null: false
      t.references :repository, foreign_key: { to_table: :git_repositories }, type: :uuid, null: true
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid, null: true
      t.string :name, null: false
      t.integer :version, default: 1
      t.string :status, default: "draft"
      t.jsonb :risk_tiers, default: -> { "'[]'::jsonb" }
      t.jsonb :merge_policy, default: -> { "'{}'::jsonb" }
      t.jsonb :docs_drift_rules, default: -> { "'{}'::jsonb" }
      t.jsonb :evidence_requirements, default: -> { "'{}'::jsonb" }
      t.jsonb :remediation_config, default: -> { "'{}'::jsonb" }
      t.jsonb :preflight_config, default: -> { "'{}'::jsonb" }
      t.jsonb :metadata, default: -> { "'{}'::jsonb" }
      t.datetime :activated_at
      t.timestamps
    end

    add_index :ai_code_factory_risk_contracts, [:account_id, :repository_id, :status], name: "idx_cf_contracts_account_repo_status"

    create_table :ai_code_factory_review_states, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, null: false
      t.references :risk_contract, foreign_key: { to_table: :ai_code_factory_risk_contracts }, type: :uuid, null: false
      t.references :repository, foreign_key: { to_table: :git_repositories }, type: :uuid, null: true
      t.integer :pr_number, null: false
      t.string :head_sha, null: false
      t.string :status, default: "pending"
      t.string :risk_tier
      t.jsonb :required_checks, default: -> { "'[]'::jsonb" }
      t.jsonb :completed_checks, default: -> { "'[]'::jsonb" }
      t.boolean :evidence_verified, default: false
      t.boolean :all_checks_passed, default: false
      t.integer :review_findings_count, default: 0
      t.integer :critical_findings_count, default: 0
      t.integer :remediation_attempts, default: 0
      t.integer :bot_threads_resolved, default: 0
      t.string :stale_reason
      t.datetime :reviewed_at
      t.jsonb :metadata, default: -> { "'{}'::jsonb" }
      t.timestamps
    end

    add_index :ai_code_factory_review_states, [:repository_id, :pr_number, :head_sha], unique: true, name: "idx_cf_review_states_repo_pr_sha"
    add_index :ai_code_factory_review_states, [:account_id, :status], name: "idx_cf_review_states_account_status"

    create_table :ai_code_factory_evidence_manifests, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, null: false
      t.references :review_state, foreign_key: { to_table: :ai_code_factory_review_states }, type: :uuid, null: false
      t.string :manifest_type, null: false
      t.string :status, default: "pending"
      t.jsonb :assertions, default: -> { "'[]'::jsonb" }
      t.jsonb :artifacts, default: -> { "'[]'::jsonb" }
      t.jsonb :verification_result, default: -> { "'{}'::jsonb" }
      t.datetime :captured_at
      t.datetime :verified_at
      t.jsonb :metadata, default: -> { "'{}'::jsonb" }
      t.timestamps
    end

    create_table :ai_code_factory_harness_gaps, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, null: false
      t.references :risk_contract, foreign_key: { to_table: :ai_code_factory_risk_contracts }, type: :uuid, null: true
      t.string :incident_source, null: false
      t.string :incident_id, null: false
      t.text :description, null: false
      t.string :status, default: "open"
      t.string :severity, default: "medium"
      t.boolean :test_case_added, default: false
      t.string :test_case_reference
      t.datetime :sla_deadline
      t.boolean :sla_met
      t.text :resolution_notes
      t.datetime :resolved_at
      t.jsonb :metadata, default: -> { "'{}'::jsonb" }
      t.timestamps
    end

    add_index :ai_code_factory_harness_gaps, [:account_id, :status], name: "idx_cf_harness_gaps_account_status"
    add_index :ai_code_factory_harness_gaps, [:incident_id], name: "idx_cf_harness_gaps_incident"
  end
end
