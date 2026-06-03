# frozen_string_literal: true

# Phase-2 (provision_fleet) job for the system_agent_fleet mission template.
# Provisions N members, enrolls each as an enabled peer, and grants L2 +
# L2.5 capabilities. Runs only after the review_fleet gate is approved.
class AiAgentFleetProvisionJob < AiAgentFleetPhaseJob
  private

  def phase
    "provision_fleet"
  end
end
