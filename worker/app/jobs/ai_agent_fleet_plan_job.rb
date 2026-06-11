# frozen_string_literal: true

# Phase-0 (plan_fleet) job for the system_agent_fleet mission template (L3).
# Validates the fleet_spec + composes the plan; the mission then advances to the
# review_fleet approval gate. Shared body: AiAgentFleetPhaseExecution.
class AiAgentFleetPlanJob < BaseJob
  include AiSuspensionCheckConcern
  include AiAgentFleetPhaseExecution

  sidekiq_options queue: "ai_execution", retry: 3

  PHASE = "plan_fleet"
end
