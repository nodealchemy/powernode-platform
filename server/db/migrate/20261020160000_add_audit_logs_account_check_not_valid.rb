# frozen_string_literal: true

# audit_logs.account_id was made nullable for platform-scoped rows (account teardown). The
# column no longer enforces tenancy on its own, so this CHECK does: a row may have no account
# only when its action is one of the platform-scoped teardown actions
# (AuditActions::PLATFORM_SCOPED_ACTIONS; a new platform-scoped action needs a migration here).
#
# Added NOT VALID so it takes only a brief lock; the next migration VALIDATEs it separately.
class AddAuditLogsAccountCheckNotValid < ActiveRecord::Migration[8.1]
  PLATFORM_ACTIONS = %w[account.destroyed account.teardown_key_revoked account.teardown_key_audit_retained].freeze

  def up
    quoted = PLATFORM_ACTIONS.map { |a| connection.quote(a) }.join(", ")
    add_check_constraint :audit_logs, "account_id IS NOT NULL OR action IN (#{quoted})",
                         name: "chk_audit_logs_account_unless_platform", validate: false
  end

  def down
    remove_check_constraint :audit_logs, name: "chk_audit_logs_account_unless_platform"
  end
end
