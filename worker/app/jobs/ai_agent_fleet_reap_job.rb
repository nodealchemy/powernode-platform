# frozen_string_literal: true

# Phase-5 (reap) job for the system_agent_fleet mission template.
# Terminates (or returns to pool) the ephemeral members and disables their
# peers, then the mission completes.
class AiAgentFleetReapJob < AiAgentFleetPhaseJob
  private

  def phase
    "reap"
  end
end
