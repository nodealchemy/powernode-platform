# frozen_string_literal: true

class CreateAiScheduledMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_scheduled_messages, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :conversation, type: :uuid, null: false, foreign_key: { to_table: :ai_conversations }
      t.references :user, type: :uuid, null: false, foreign_key: true

      t.string :scheduling_mode, null: false
      t.jsonb :schedule_config, default: -> { "'{}'" }, null: false
      t.text :message_template, null: false
      t.jsonb :template_variables, default: -> { "'{}'" }, null: false
      t.string :status, default: "active", null: false
      t.datetime :next_scheduled_at
      t.datetime :last_executed_at
      t.integer :execution_count, default: 0, null: false
      t.integer :max_executions

      # Scheduling concern columns
      t.datetime :last_scheduled_at
      t.boolean :schedule_paused, default: false, null: false
      t.datetime :schedule_paused_at
      t.string :schedule_paused_reason
      t.integer :daily_iteration_count, default: 0, null: false
      t.date :daily_iteration_reset_at

      t.timestamps
    end

    add_index :ai_scheduled_messages, [:account_id, :status], name: "index_ai_scheduled_messages_on_account_and_status"
    add_index :ai_scheduled_messages, [:status, :next_scheduled_at], name: "index_ai_scheduled_messages_on_status_and_next_at"
  end
end
