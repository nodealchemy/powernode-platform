# frozen_string_literal: true

# ExternalAgentCardFetchJob - Fetches and caches agent cards from external A2A agents
class ExternalAgentCardFetchJob < ApplicationJob
  queue_as :default

  def perform(external_agent_id)
    external_agent = ExternalAgent.find_by(id: external_agent_id)
    return unless external_agent

    external_agent.fetch_agent_card!
  end
end
