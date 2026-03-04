# frozen_string_literal: true

class CreateAiSelfChallenges < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_self_challenges, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :challenger_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.references :executor_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.references :validator_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.references :ai_skill, type: :uuid, foreign_key: { to_table: :ai_skills }

      t.string :challenge_id, null: false
      t.string :status, null: false, default: "pending"
      t.string :difficulty, null: false, default: "medium"
      t.text :challenge_prompt
      t.jsonb :expected_criteria, default: {}
      t.text :execution_result
      t.jsonb :validation_result, default: {}
      t.decimal :quality_score, precision: 5, scale: 4

      t.timestamps
    end

    add_index :ai_self_challenges, :challenge_id, unique: true
    add_index :ai_self_challenges, [:account_id, :status], name: "idx_self_challenges_account_status"
    add_index :ai_self_challenges, [:challenger_agent_id, :status], name: "idx_self_challenges_agent_status"
  end
end
