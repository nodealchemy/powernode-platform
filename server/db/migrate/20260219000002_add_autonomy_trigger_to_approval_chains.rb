# frozen_string_literal: true

class AddAutonomyTriggerToApprovalChains < ActiveRecord::Migration[8.0]
  def up
    # Add 'autonomy_action' to the check_chain_trigger_type constraint
    execute <<~SQL
      ALTER TABLE ai_approval_chains DROP CONSTRAINT IF EXISTS check_chain_trigger_type;
      ALTER TABLE ai_approval_chains ADD CONSTRAINT check_chain_trigger_type
        CHECK (trigger_type IN ('workflow_deploy', 'agent_deploy', 'high_cost', 'sensitive_data', 'model_change', 'policy_override', 'manual', 'autonomy_action'));
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE ai_approval_chains DROP CONSTRAINT IF EXISTS check_chain_trigger_type;
      ALTER TABLE ai_approval_chains ADD CONSTRAINT check_chain_trigger_type
        CHECK (trigger_type IN ('workflow_deploy', 'agent_deploy', 'high_cost', 'sensitive_data', 'model_change', 'policy_override', 'manual'));
    SQL
  end
end
