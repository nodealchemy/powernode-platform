# frozen_string_literal: true

class CreateAiKillSwitchEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_kill_switch_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :triggered_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.text :reason
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_kill_switch_events, [:account_id, :event_type]
    add_index :ai_kill_switch_events, [:account_id, :created_at]
  end
end
