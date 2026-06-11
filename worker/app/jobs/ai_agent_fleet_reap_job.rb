# frozen_string_literal: true

# Phase-5 (reap) job for the system_agent_fleet mission template (L3).
# Terminates (or returns to pool) the ephemeral members and disables their
# peers; the mission then completes. Shared body: AiAgentFleetPhaseExecution.
class AiAgentFleetReapJob < BaseJob
  include AiSuspensionCheckConcern
  include AiAgentFleetPhaseExecution

  sidekiq_options queue: "ai_execution", retry: 3

  PHASE = "reap"
end
