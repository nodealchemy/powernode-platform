# frozen_string_literal: true

class CreateIntegrationInstances < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_instances, id: :uuid do |t|
      # Relationships
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :integration_template, null: false, foreign_key: true, type: :uuid
      t.references :integration_credential, foreign_key: true, type: :uuid
      t.references :created_by_user, foreign_key: { to_table: :users }, type: :uuid

      # Instance Identity
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      # Status Management
      t.string :status, default: "pending"  # pending, active, paused, error, disabled

      # Configuration (overrides from template)
      t.jsonb :configuration, default: {}  # Instance-specific configuration
      t.jsonb :runtime_state, default: {}  # Current state of the integration
      t.jsonb :health_metrics, default: {}  # Health check results

      # Execution Statistics
      t.integer :execution_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.decimal :average_duration_ms, precision: 10, scale: 2
      t.datetime :last_executed_at
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.text :last_error

      # Health Tracking
      t.datetime :last_health_check_at
      t.string :health_status  # healthy, degraded, unhealthy, unknown
      t.integer :consecutive_failures, default: 0

      t.timestamps
    end

    add_index :integration_instances, [:account_id, :slug], unique: true
    add_index :integration_instances, :status
    add_index :integration_instances, :health_status
    add_index :integration_instances, [:account_id, :status], name: "idx_instances_account_status"
  end
end
