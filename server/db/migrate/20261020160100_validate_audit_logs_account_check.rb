# frozen_string_literal: true

# Second step: scan existing rows against chk_audit_logs_account_unless_platform without
# blocking writes. Every existing row has an account, so this passes.
class ValidateAuditLogsAccountCheck < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :audit_logs, name: "chk_audit_logs_account_unless_platform"
  end

  def down; end
end
