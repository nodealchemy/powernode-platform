# frozen_string_literal: true

# Component status plane — the index the retention prune actually uses.
#
# A1 review L1 removed an index whose comment named a query that did not
# exist. This one is the opposite case, and the difference is worth stating so
# the two are not confused: the predicate is written down, it is the only thing
# Platform::Status::EventRetention issues, and no existing index can serve it.
#
#   DELETE FROM platform_status_events WHERE occurred_at < $1   (bounded by id)
#
# The table's two existing indexes lead with `account_id` and with
# `component_kind` respectively, so neither helps a scan keyed on `occurred_at`
# alone — the prune would seq-scan a table that grows with every transition,
# once per sweep. The prune deliberately does NOT loop accounts to reuse
# [account_id, occurred_at]: retention is a global janitorial concern, and
# issuing one delete per account per minute to avoid one index is the wrong
# trade.
class AddOccurredAtIndexToPlatformStatusEvents < ActiveRecord::Migration[8.0]
  def change
    add_index :platform_status_events, :occurred_at,
              name: "index_platform_status_events_on_occurred_at"
  end
end
