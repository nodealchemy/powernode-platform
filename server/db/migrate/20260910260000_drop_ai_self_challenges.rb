# frozen_string_literal: true

# Increment D6 — the self-challenge subsystem is deleted, so its table goes too.
#
# It was built three times over and wired zero times (audit §6.3):
# `generate_challenge!` created a row at `generating` and enqueued nothing, the
# scheduler job appeared in no `sidekiq*.yml`, the challenged agent graded
# itself with a 0.5 default on a parse failure, and no result ever reached a
# trust score or a skill. Three MCP verbs advertised the capability.
#
# REVERSIBLE IN STRUCTURE, NOT IN DATA. `#down` recreates the table, its
# indexes and its foreign keys, so a rollback succeeds and leaves a loadable
# schema. It deliberately does not raise ActiveRecord::IrreversibleMigration.
# The ROWS are gone: nothing in the platform can reconstruct them, and nothing
# ever read them, so a rolled-back table comes back empty.
class DropAiSelfChallenges < ActiveRecord::Migration[8.1]
  # `if_exists` because the postcondition is "the table is absent", and a
  # deployment where it already is (a fresh install seeded from a schema.rb
  # that no longer carries it) must not fail on the way to that state.
  def up
    drop_table :ai_self_challenges, if_exists: true
  end

  def down
    create_table :ai_self_challenges, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :ai_skill, type: :uuid, foreign_key: true
      t.string :challenge_id, null: false
      t.text :challenge_prompt
      t.references :challenger_agent, null: false, type: :uuid,
                   foreign_key: { to_table: :ai_agents }
      t.string :difficulty, default: "medium", null: false
      t.text :execution_result
      t.references :executor_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.jsonb :expected_criteria, default: {}
      t.decimal :quality_score, precision: 5, scale: 4
      t.string :status, default: "pending", null: false
      t.jsonb :validation_result, default: {}
      t.references :validator_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.timestamps
    end

    add_index :ai_self_challenges, %i[account_id status]
    add_index :ai_self_challenges, :challenge_id, unique: true
    add_index :ai_self_challenges, %i[challenger_agent_id status]
  end
end
