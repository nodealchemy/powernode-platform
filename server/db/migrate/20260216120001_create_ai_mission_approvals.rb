# frozen_string_literal: true

class CreateAiMissionApprovals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_mission_approvals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :mission, type: :uuid, null: false, foreign_key: { to_table: :ai_missions }
      t.references :account, type: :uuid, null: false, index: true
      t.references :user, type: :uuid, null: false

      t.string :gate, null: false
      t.string :decision, null: false
      t.text :comment
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_mission_approvals, [:mission_id, :gate]
  end
end
