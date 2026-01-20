# frozen_string_literal: true

# Remove the conflicting coordination_strategy constraint from the original
# ai_agent_teams migration. The newer migration (20260119000007) added an updated
# constraint with more sophisticated coordination strategies:
# - Original: manager_worker, peer_to_peer, hybrid
# - New: manager_led, consensus, auction, round_robin, priority_based
#
# Both constraints cannot coexist as they define different allowed values.
class RemoveConflictingCoordinationStrategyConstraint < ActiveRecord::Migration[8.1]
  def up
    # Remove the old constraint that conflicts with the newer check_coordination_strategy
    remove_check_constraint :ai_agent_teams, name: 'ai_agent_teams_coordination_strategy_check'
  end

  def down
    # Restore the old constraint (note: this may fail if data uses new values)
    add_check_constraint :ai_agent_teams,
                         "coordination_strategy IN ('manager_worker', 'peer_to_peer', 'hybrid')",
                         name: 'ai_agent_teams_coordination_strategy_check'
  end
end
