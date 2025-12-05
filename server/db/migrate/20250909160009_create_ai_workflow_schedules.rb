# frozen_string_literal: true

class CreateAiWorkflowSchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_schedules, id: :uuid do |t|
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false, limit: 255
      t.text :description
      t.string :cron_expression, null: false
      t.string :timezone, null: false, default: 'UTC'
      t.string :status, null: false, default: 'active'
      t.jsonb :input_variables, null: false, default: {}
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :starts_at
      t.datetime :ends_at
      t.datetime :next_execution_at
      t.datetime :last_execution_at
      t.integer :execution_count, null: false, default: 0
      t.integer :max_executions
      t.boolean :is_active, null: false, default: true
      t.timestamps

      t.index [:ai_workflow_id, :status]
      t.index [:next_execution_at, :is_active]
      t.index :cron_expression
      t.index :timezone
      t.index :last_execution_at
    end

    add_check_constraint :ai_workflow_schedules,
      "status IN ('active', 'paused', 'disabled', 'expired')",
      name: 'ai_workflow_schedules_status_check'

    add_check_constraint :ai_workflow_schedules,
      "execution_count >= 0",
      name: 'ai_workflow_schedules_execution_count_check'

    add_check_constraint :ai_workflow_schedules,
      "(max_executions IS NULL) OR (max_executions > 0)",
      name: 'ai_workflow_schedules_max_executions_check'

    add_check_constraint :ai_workflow_schedules,
      "(ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at > starts_at)",
      name: 'ai_workflow_schedules_date_range_check'
  end
end