# frozen_string_literal: true

class AddApprovalChainToInterventionPolicies < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_intervention_policies, :approval_chain, type: :uuid, null: true,
                                                              foreign_key: { to_table: :ai_approval_chains },
                                                              index: true
  end
end
