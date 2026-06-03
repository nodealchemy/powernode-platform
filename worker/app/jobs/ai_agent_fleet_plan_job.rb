# frozen_string_literal: true

# Phase-0 (plan_fleet) job for the system_agent_fleet mission template.
# Validates the fleet_spec + composes the normalized plan, then the mission
# advances to the review_fleet approval gate.
class AiAgentFleetPlanJob < AiAgentFleetPhaseJob
  private

  def phase
    "plan_fleet"
  end
end
