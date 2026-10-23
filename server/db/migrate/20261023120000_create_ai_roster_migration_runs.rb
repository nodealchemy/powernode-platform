# frozen_string_literal: true

# One reusable ledger for every roster migration step (0.3.0 roster
# activation): the shadow repair (R1), the team rosters (R2), the fleet
# (R4). A step writes one row per record it moves, so the step can be reversed
# from its ledger alone: which run, which table and row, from which agent
# (or other id) to which. Additive; nothing reads it but the repair tasks.
class CreateAiRosterMigrationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_roster_migration_runs, id: :uuid, default: -> { "uuidv7()" } do |t|
      # Which migration step wrote the row, e.g. "shadow_repair".
      t.string :kind, null: false
      # One id per APPLY, shared by every row it wrote; ROLLBACK=<run_id> names it.
      t.uuid :run_id, null: false
      t.uuid :account_id
      t.string :table_name, null: false
      t.uuid :record_id, null: false
      t.uuid :from_id
      t.uuid :to_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :ai_roster_migration_runs, %i[kind run_id], name: "idx_ai_roster_migration_runs_run"
    add_index :ai_roster_migration_runs, %i[table_name record_id], name: "idx_ai_roster_migration_runs_record"
  end
end
