# frozen_string_literal: true

# Self-Serve Hardening M4 — wire an optional team-isolation pointer onto
# `ai_missions`. Backed by `account_team_delegations` (M4 Slice A), but
# nullable so existing missions and accounts without per-team scoping
# continue to work unchanged.
#
# `Ai::Mission#delegation` returns `Account::TeamDelegation`. Slice C
# (second-signature) and Slice D (IP allowlist) read from this column to
# scope behavior per team.
class AddDelegationToAiMissions < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_missions,
                  :delegation,
                  type: :uuid,
                  null: true,
                  foreign_key: { to_table: :account_team_delegations, on_delete: :nullify }
  end
end
