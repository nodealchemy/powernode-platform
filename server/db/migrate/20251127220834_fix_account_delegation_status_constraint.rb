# frozen_string_literal: true

class FixAccountDelegationStatusConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the old constraint
    remove_check_constraint :account_delegations, name: "valid_delegation_status"

    # Add the corrected constraint with 'revoked' status
    add_check_constraint :account_delegations,
                         "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'revoked'::character varying::text])",
                         name: "valid_delegation_status"
  end

  def down
    # Remove the corrected constraint
    remove_check_constraint :account_delegations, name: "valid_delegation_status"

    # Restore the old constraint (in case of rollback)
    add_check_constraint :account_delegations,
                         "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'expired'::character varying::text])",
                         name: "valid_delegation_status"
  end
end
