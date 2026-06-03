# frozen_string_literal: true

# Phase-4 (aggregate) job for the system_agent_fleet mission template (L3).
# Collects per-subtask result envelopes into the mission's fleet report.
# Shared body: AiAgentFleetPhaseExecution.
class AiAgentFleetAggregateJob < BaseJob
  include AiAgentFleetPhaseExecution

  sidekiq_options queue: "ai_execution", retry: 3

  PHASE = "aggregate"
end
