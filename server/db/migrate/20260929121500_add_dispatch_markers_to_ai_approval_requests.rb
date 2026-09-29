# frozen_string_literal: true

# IMP-0213523480d1 — make a stranded post-approval dispatch observable.
#
# IMP-9ce0ed39c557 moved the approved-arm dispatch in
# Ai::ApprovalRequest#notify_source_of_decision to after commit, so the flip to
# "approved" now commits BEFORE the dispatch runs. A process that dies in
# between leaves the request approved with execution_status nil — the same
# state a dispatch that ran and reported a no-op leaves, so no existing column
# can tell the two apart:
#   * execution_status nil means "nothing to declare" for both;
#   * completed_at is stamped by the flip itself, before either;
#   * the operation's own status covers one source type out of five, and an
#     Ai::DeferredOperation is still `pending` for a moment inside a dispatch
#     that has started.
#
# Four stamps, all written by the approval path or its reconciler:
#   dispatch_scheduled_at — in the flip's own transaction, when the approved
#     arm registers its post-commit dispatch. It commits or rolls back with
#     the approval, so it exists exactly when a dispatch is owed. It is also
#     the grace-window clock, and what keeps a request that never had a
#     dispatchable source (and, bar the backfill below, every row approved
#     before this column existed) out of the reconciler's reach.
#   dispatch_started_at — by a conditional update at the start of that
#     dispatch, and the claim the reconciler competes for.
#   dispatch_finished_at — on every terminal path of a claimed dispatch
#     (executed, no-op, failed, nothing to dispatch to). Started but never
#     finished is a dispatch that died mid-flight: execution_status nil there
#     is NOT a reported no-op, and without this stamp the two read the same.
#   dispatch_interrupt_signalled_at — the reconciler's once-only claim on
#     signalling such an interrupted dispatch. Signal only: the side effect may
#     have happened, so nothing re-runs or fails it.
# Owed but never started, past the grace window, is the stranded state;
# started but never finished, past a much longer window, is the interrupted one.
#
# Backfilled for the one source type where "owed, never started" is provable
# from existing rows: an approved request whose Ai::DeferredOperation is still
# `pending` with no declared outcome. A dispatch that ran would have moved the
# operation (#execute_now! approves it before anything else), and one that
# raised would have declared "failed". Those are the rows stranded since
# IMP-9ce0ed39c557 shipped; the reconciler then settles them like any other.
# No other source type is backfilled: for them a dispatch that ran and reported
# a no-op leaves exactly this state, so marking them would fail real no-ops.
# One set-based UPDATE on typed columns — nothing on the boot path that can
# raise on a production value.
class AddDispatchMarkersToAiApprovalRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :ai_approval_requests, :dispatch_scheduled_at, :datetime
    add_column :ai_approval_requests, :dispatch_started_at, :datetime
    add_column :ai_approval_requests, :dispatch_finished_at, :datetime
    add_column :ai_approval_requests, :dispatch_interrupt_signalled_at, :datetime

    # The reconciler's two scans, per account, oldest first. Partial, so each
    # holds only its (normally empty) set.
    add_index :ai_approval_requests, %i[account_id dispatch_scheduled_at],
              name: "index_ai_approval_requests_on_owed_dispatch",
              where: "dispatch_scheduled_at IS NOT NULL AND dispatch_started_at IS NULL " \
                     "AND execution_status IS NULL"
    add_index :ai_approval_requests, %i[account_id dispatch_started_at],
              name: "index_ai_approval_requests_on_unfinished_dispatch",
              where: "dispatch_started_at IS NOT NULL AND dispatch_finished_at IS NULL " \
                     "AND dispatch_interrupt_signalled_at IS NULL"

    backfill_owed_dispatches
  end

  def down
    remove_index :ai_approval_requests, name: "index_ai_approval_requests_on_unfinished_dispatch"
    remove_index :ai_approval_requests, name: "index_ai_approval_requests_on_owed_dispatch"
    remove_column :ai_approval_requests, :dispatch_interrupt_signalled_at
    remove_column :ai_approval_requests, :dispatch_finished_at
    remove_column :ai_approval_requests, :dispatch_started_at
    remove_column :ai_approval_requests, :dispatch_scheduled_at
  end

  # Its own method so spec/db/migrate can pin the predicate against real rows
  # once the columns exist.
  def backfill_owed_dispatches
    execute <<~SQL.squish
      UPDATE ai_approval_requests r
         SET dispatch_scheduled_at = COALESCE(r.completed_at, r.updated_at)
        FROM ai_deferred_operations o
       WHERE r.source_type = 'Ai::DeferredOperation'
         AND o.id = r.source_id
         AND r.status = 'approved'
         AND r.execution_status IS NULL
         AND o.status = 'pending'
    SQL
  end
end
