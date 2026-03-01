# frozen_string_literal: true

class CreateAiRemediationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_remediation_logs, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :trigger_source, null: false
      t.string :trigger_event, null: false
      t.string :action_type, null: false
      t.jsonb :action_config, default: {}
      t.jsonb :before_state, default: {}
      t.jsonb :after_state, default: {}
      t.string :result, null: false
      t.text :result_message
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :ai_remediation_logs, [:account_id, :executed_at]
    add_index :ai_remediation_logs, :action_type
    add_index :ai_remediation_logs, :result
  end
end
