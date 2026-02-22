# frozen_string_literal: true

# WellKnownController - Serves well-known resources for protocol discovery
# Implements A2A Agent Card, OAuth Protected Resource (RFC 9728),
# and OAuth Authorization Server Metadata (RFC 8414).
class WellKnownController < ActionController::API
  # GET /.well-known/agent-card.json
  # Returns the platform's A2A Agent Card for discovery
  def agent_card
    card = A2a::AgentCardService.platform_card(request.base_url)
    render json: card
  end

  # GET /.well-known/oauth-protected-resource
  # RFC 9728 — tells MCP clients which authorization server protects /api/v1/mcp
  def oauth_protected_resource
    render json: {
      resource: "#{request.base_url}/api/v1/mcp",
      authorization_servers: [request.base_url],
      bearer_methods_supported: ["header"],
      scopes_supported: oauth_scopes
    }
  end

  # GET /.well-known/oauth-authorization-server
  # RFC 8414 — full authorization server metadata for OAuth 2.1 discovery
  def oauth_authorization_server
    base = request.base_url

    render json: {
      issuer: base,
      authorization_endpoint: "#{base}/api/v1/oauth/authorize",
      token_endpoint: "#{base}/api/v1/oauth/token",
      registration_endpoint: "#{base}/api/v1/oauth/register",
      revocation_endpoint: "#{base}/api/v1/oauth/revoke",
      introspection_endpoint: "#{base}/api/v1/oauth/introspect",
      response_types_supported: ["code"],
      grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: oauth_scopes
    }
  end

  private

  def oauth_scopes
    %w[read write admin billing users webhooks workflows files]
  end
end
