# frozen_string_literal: true

# Separation of duty: one person, one decision per step of an approval request.
#
# Ai::ApprovalRequest#can_approve? refuses a second decision from the same
# approver on the same step. This unique index is the database's half: it holds
# the rule whatever the application path does, including any path that does not
# take the request lock, so two concurrent calls from the same approver can never
# both land and both count toward required_approvals.
#
# EXISTING DUPLICATES ARE AUDIT EVIDENCE. They are never deleted or merged here.
# If any exist, the migration stops and names how many (approval request, step,
# approver) groups hold more than one decision, and an operator decides.
class AddOneDecisionPerApproverPerStepToAiApprovalDecisions < ActiveRecord::Migration[8.0]
  INDEX_NAME = "idx_ai_approval_decisions_one_per_approver_per_step"
  COLUMNS = %i[approval_request_id step_number approver_id].freeze

  def up
    duplicates = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (
        SELECT 1 FROM ai_approval_decisions
        GROUP BY approval_request_id, step_number, approver_id
        HAVING COUNT(*) > 1
      ) AS duplicate_groups
    SQL

    if duplicates.positive?
      raise ActiveRecord::MigrationError,
            "#{duplicates} (approval request, step, approver) group(s) in ai_approval_decisions hold more " \
            "than one decision. They are audit evidence and are not changed automatically: review them, " \
            "then run this migration again."
    end

    add_index :ai_approval_decisions, COLUMNS, unique: true, name: INDEX_NAME
  end

  def down
    remove_index :ai_approval_decisions, name: INDEX_NAME
  end
end
