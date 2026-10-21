# frozen_string_literal: true

# Platform-scoped audit rows (Account teardown review #2). When an account is
# destroyed its key-operation audit trail and one `account.destroyed` record must
# SURVIVE it, so they cannot reference the account. They live in audit_logs, not a
# second table, because that table owns the one global tamper-evident chain
# (sequence_number / previous_hash / integrity_hash): a second table would need its
# own chain and service and could not be verified together with the rest.
#
# The foreign key to accounts stays: NULL satisfies it, and a row that still points at
# an account still cannot outlive it. The model (not the column) enforces that only
# platform-scoped actions may have a NULL account_id, so tenant rows keep their invariant.
class AllowPlatformScopedAuditLogs < ActiveRecord::Migration[8.1]
  def change
    change_column_null :audit_logs, :account_id, true
  end
end
