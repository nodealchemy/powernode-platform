# frozen_string_literal: true

class CreateAiWorkflowTriggers < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_triggers, id: :uuid do |t|
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :trigger_type, null: false
      t.string :status, null: false, default: 'active'
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.string :webhook_url, limit: 2048
      t.string :webhook_secret
      t.string :schedule_cron
      t.datetime :next_execution_at
      t.datetime :last_triggered_at
      t.integer :trigger_count, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.timestamps

      t.index [ :ai_workflow_id, :trigger_type ]
      t.index [ :ai_workflow_id, :status ]
      t.index [ :trigger_type, :is_active ]
      t.index :next_execution_at
      t.index :schedule_cron
      t.index :webhook_url
    end

    add_check_constraint :ai_workflow_triggers,
      "trigger_type IN ('manual', 'webhook', 'schedule', 'event', 'api_call')",
      name: 'ai_workflow_triggers_type_check'

    add_check_constraint :ai_workflow_triggers,
      "status IN ('active', 'paused', 'disabled', 'error')",
      name: 'ai_workflow_triggers_status_check'

    add_check_constraint :ai_workflow_triggers,
      "(trigger_type != 'schedule') OR (schedule_cron IS NOT NULL)",
      name: 'ai_workflow_triggers_schedule_required_check'

    add_check_constraint :ai_workflow_triggers,
      "(trigger_type != 'webhook') OR (webhook_url IS NOT NULL)",
      name: 'ai_workflow_triggers_webhook_required_check'
  end
end
