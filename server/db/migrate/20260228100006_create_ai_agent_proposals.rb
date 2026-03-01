# frozen_string_literal: true

class CreateAiAgentProposals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_proposals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :ai_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.references :target_user, type: :uuid, foreign_key: { to_table: :users }
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :conversation, type: :uuid, foreign_key: { to_table: :ai_conversations }

      t.string :proposal_type, null: false
      t.string :title, null: false, limit: 255
      t.text :description
      t.text :rationale
      t.string :status, null: false, default: "pending_review"
      t.string :priority, null: false, default: "medium"
      t.jsonb :impact_assessment, default: {}
      t.jsonb :proposed_changes, default: {}
      t.datetime :review_deadline
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :ai_agent_proposals, :status
    add_index :ai_agent_proposals, :proposal_type
    add_index :ai_agent_proposals, [:account_id, :status]
    add_index :ai_agent_proposals, :review_deadline, where: "status = 'pending_review'"
  end
end
