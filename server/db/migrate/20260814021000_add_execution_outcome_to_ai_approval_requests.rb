# frozen_string_literal: true

# IMP-4bbb4227ac8a. The execute-on-approval dispatch
# (Ai::ApprovalRequest#notify_source_of_decision) rescued executor failures and
# only logged, so an approved action that failed left the request "approved"
# with no declared outcome anywhere. These columns carry that declaration:
#
#   execution_status — nil until a post-approval dispatch actually runs, then
#                      "succeeded" | "failed" (the approval `status` vocabulary
#                      and its check constraint are untouched — approval
#                      semantics are not execution semantics)
#   execution_error  — "ErrorClass: message" detail when the dispatch failed
#
# Additive only; no backfill (historical rows genuinely have no declared
# outcome — that is the defect being closed, not data to invent).
class AddExecutionOutcomeToAiApprovalRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_approval_requests, :execution_status, :string
    add_column :ai_approval_requests, :execution_error, :text
    # The runtime writer is update_columns (it must not re-enter the callback
    # chain it runs inside), which bypasses model validations — so the
    # vocabulary is enforced here, like the status column's check constraint.
    add_check_constraint :ai_approval_requests,
                         "execution_status IS NULL OR execution_status IN ('succeeded', 'failed')",
                         name: "check_execution_status"
  end
end
