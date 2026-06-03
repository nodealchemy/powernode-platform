# frozen_string_literal: true

# Phase-4 (aggregate) job for the system_agent_fleet mission template.
# Collects per-subtask result envelopes into the mission's fleet report.
class AiAgentFleetAggregateJob < AiAgentFleetPhaseJob
  private

  def phase
    "aggregate"
  end
end
