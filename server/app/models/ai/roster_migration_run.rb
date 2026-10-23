# frozen_string_literal: true

module Ai
  # One reusable ledger for the roster migration steps (0.3.0 roster activation):
  # a row per record a step moved — kind (the step, e.g. "shadow_repair"), run_id
  # (one per APPLY), table_name and record_id (the row moved), from_id and to_id
  # (what it pointed at before and after), metadata. A step is reversed from its
  # ledger alone. Append-only: nothing updates or deletes a row.
  class RosterMigrationRun < ApplicationRecord
    self.table_name = "ai_roster_migration_runs"

    validates :kind, :run_id, :table_name, :record_id, presence: true

    scope :for_run, ->(kind, run_id) { where(kind: kind, run_id: run_id) }

    before_update { throw :abort }
  end
end
