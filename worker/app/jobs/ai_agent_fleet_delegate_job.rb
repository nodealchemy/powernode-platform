# frozen_string_literal: true

# Phase-3 (delegate) job for the system_agent_fleet mission template.
# Assigns subtasks to members and records the A2A sub-delegation authorization
# graph (hybrid/a2a delegation modes).
class AiAgentFleetDelegateJob < AiAgentFleetPhaseJob
  private

  def phase
    "delegate"
  end
end
