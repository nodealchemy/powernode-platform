# frozen_string_literal: true

class CreateAiAgentFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_feedbacks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :ai_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }

      t.string :context_type
      t.uuid :context_id
      t.string :feedback_type, null: false
      t.integer :rating, null: false
      t.text :comment
      t.boolean :applied_to_trust, null: false, default: false

      t.timestamps
    end

    add_index :ai_agent_feedbacks, [:context_type, :context_id]
    add_index :ai_agent_feedbacks, :feedback_type
    add_index :ai_agent_feedbacks, [:ai_agent_id, :applied_to_trust]
  end
end
