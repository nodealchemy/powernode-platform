# frozen_string_literal: true

# Phase-3 (delegate) job for the system_agent_fleet mission template (L3).
# Assigns subtasks to members + records the A2A sub-delegation authorization
# graph (hybrid/a2a modes). Shared body: AiAgentFleetPhaseExecution.
class AiAgentFleetDelegateJob < BaseJob
  include AiAgentFleetPhaseExecution

  sidekiq_options queue: "ai_execution", retry: 3

  PHASE = "delegate"
end
