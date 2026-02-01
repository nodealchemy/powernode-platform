# frozen_string_literal: true

# WellKnownController - Serves well-known resources for protocol discovery
# Implements A2A Agent Card at /.well-known/agent-card.json
class WellKnownController < ActionController::API
  # GET /.well-known/agent-card.json
  # Returns the platform's A2A Agent Card for discovery
  def agent_card
    card = A2a::AgentCardService.platform_card(request.base_url)
    render json: card
  end
end
