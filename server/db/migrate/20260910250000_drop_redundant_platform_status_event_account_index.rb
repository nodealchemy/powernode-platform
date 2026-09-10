# frozen_string_literal: true

# Component status plane — A2 review L2.
#
# `t.references :account` auto-created `index_platform_status_events_on_account_id`,
# and the same migration then added `[account_id, occurred_at]`, whose leading
# column serves everything the single-column index would. Two indexes
# maintained on a table written once per transition, one of them for nothing.
#
# Same shape as A1 review L1, and the same reasoning: an index is a write cost
# on every insert forever, so one that no query needs is not neutral. Note the
# difference from L1 though — that one was ADDED by hand on a wrong premise;
# this one was generated, which is why CLAUDE.md's convention is
# `t.references ... type: :uuid` with no separate `add_index` and why the
# composite here needed a second look rather than the reference.
#
# A new migration rather than an edit to 20260910210000 or to the tightening
# migration: both are applied everywhere, and editing an applied migration is
# how a schema and its schema_migrations row stop agreeing.
class DropRedundantPlatformStatusEventAccountIndex < ActiveRecord::Migration[8.0]
  def up
    remove_index :platform_status_events, name: "index_platform_status_events_on_account_id"
  end

  def down
    add_index :platform_status_events, :account_id,
              name: "index_platform_status_events_on_account_id"
  end
end
