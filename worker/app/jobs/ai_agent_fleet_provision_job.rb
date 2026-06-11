# frozen_string_literal: true

# Phase-2 (provision_fleet) job for the system_agent_fleet mission template (L3).
# Provisions N members, enrolls each as an enabled peer, grants L2 + L2.5.
# Runs only after the review_fleet gate is approved. Shared body:
# AiAgentFleetPhaseExecution.
class AiAgentFleetProvisionJob < BaseJob
  include AiSuspensionCheckConcern
  include AiAgentFleetPhaseExecution

  sidekiq_options queue: "ai_execution", retry: 3

  PHASE = "provision_fleet"
end
