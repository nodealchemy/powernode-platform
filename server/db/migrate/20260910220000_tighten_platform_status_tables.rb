# frozen_string_literal: true

# Component status plane — A1 review fixes M2, L1 and the M4 contract change.
#
# A separate migration rather than an edit to the two that created these
# tables: the lane databases have already applied those, and editing an
# applied migration is how a schema and its schema_migrations row stop
# agreeing.
#
# M2 — A DELETED ACCOUNT'S ROWS WERE IMMORTAL. Both tables carried
# `foreign_key: false`, and the sweep's reap only ever scopes to the account
# being swept. A deleted account is never swept, so nothing in the platform
# could ever remove its rows: no reap path reaches them, and there was no
# database-level cascade either. 287 of 310 `account_id` columns in this
# schema carry an FK to `accounts`; these were two of the handful that did
# not, for no stated reason. `on_delete: :cascade` because a status row and
# its history are meaningless once the tenant is gone — this is derived
# state, not a record anyone audits after the fact.
#
# L1 — AN INDEX THAT MATCHED NO QUERY. `[component_kind, last_seen_sweep_at]`
# was added with the comment "the reap arm scans by kind + freshness". It does
# not: the reap predicate is account + freshness, and the other read
# (`existing_rows`) is `(account_id, component_kind)`, already served by the
# leading columns of the unique index. Nothing is added in its place — at the
# design's stated ceiling (150 components × 16 kinds) the reap does not need
# one, and an index justified by a guess is what produced this one.
#
# M4 — `to_verdict` BECOMES NULLABLE. The sweep now reports a REMOVAL (a reap,
# or a recovered wildcard row) as a transition with `to: nil`, so the event
# stream closes rather than leaving a component's last word as `down` forever.
# A removal has no destination verdict, and inventing one — "ok", say, or
# "not_measured" — would claim an observation the platform never made.
class TightenPlatformStatusTables < ActiveRecord::Migration[8.0]
  def up
    add_foreign_key :platform_component_statuses, :accounts, on_delete: :cascade
    add_foreign_key :platform_status_events, :accounts, on_delete: :cascade

    remove_index :platform_component_statuses,
                 name: "index_platform_component_statuses_on_kind_and_last_seen"

    change_column_null :platform_status_events, :to_verdict, true
  end

  def down
    change_column_null :platform_status_events, :to_verdict, false

    add_index :platform_component_statuses, %i[component_kind last_seen_sweep_at],
              name: "index_platform_component_statuses_on_kind_and_last_seen"

    remove_foreign_key :platform_status_events, :accounts
    remove_foreign_key :platform_component_statuses, :accounts
  end
end
