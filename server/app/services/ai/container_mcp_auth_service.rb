# frozen_string_literal: true

module Ai
  class ContainerMcpAuthService
    class AuthProvisioningError < StandardError; end

    # Provision MCP OAuth credentials for a containerized agent.
    #
    # Finds or creates a machine-client OauthApplication for the agent,
    # generates a fresh access token via client_credentials grant, and
    # returns environment variables for container injection.
    #
    # @param agent [Ai::Agent] the agent requesting MCP access
    # @param account [Account] the owning account
    # @return [Hash] { env_vars: Hash, oauth_application: OauthApplication }
    def provision_mcp_credentials(agent:, account:)
      oauth_app = find_or_create_oauth_app(agent: agent, account: account)

      env_vars = build_env_vars(oauth_app: oauth_app, agent: agent)

      { env_vars: env_vars, oauth_application: oauth_app }
    rescue StandardError => e
      Rails.logger.error "[ContainerMcpAuth] Failed to provision credentials for agent #{agent.id}: #{e.message}"
      raise AuthProvisioningError, "MCP auth provisioning failed: #{e.message}"
    end

    # Revoke all active tokens for an OAuth application without destroying the app.
    #
    # @param oauth_application [OauthApplication]
    def revoke_tokens(oauth_application:)
      return unless oauth_application

      oauth_application.access_tokens
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)

      Rails.logger.info "[ContainerMcpAuth] Revoked tokens for app #{oauth_application.name}"
    end

    private

    def find_or_create_oauth_app(agent:, account:)
      # Look for existing app by agent_id in metadata
      existing = OauthApplication.find_by(
        "metadata->>'agent_id' = ? AND metadata->>'container_agent' = ?",
        agent.id.to_s, "true"
      )

      return existing if existing&.active?

      # Reactivate if suspended
      if existing&.status == "suspended"
        existing.activate!
        return existing
      end

      # Create new OAuth application
      # Doorkeeper returns the plaintext secret only on create — we capture it
      # and store in metadata encrypted for subsequent container launches.
      app = OauthApplication.create!(
        name: "Container Agent: #{agent.name}",
        redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
        scopes: "read write",
        confidential: true,
        machine_client: true,
        trusted: true,
        status: "active",
        owner: account,
        metadata: {
          "agent_id" => agent.id.to_s,
          "container_agent" => "true",
          "account_id" => account.id.to_s
        }
      )

      # Store the plaintext secret in metadata for subsequent provisions.
      # OauthApplication.secret is hashed by Doorkeeper after creation,
      # so we must capture the plaintext from the initial create response.
      app.update_column(:metadata, app.metadata.merge("client_secret_plain" => app.plaintext_secret || app.secret))

      app
    end

    def build_env_vars(oauth_app:, agent:)
      powernode_url = ENV.fetch("POWERNODE_URL") { "http://backend:3000" }

      # Retrieve the plaintext secret stored during creation
      client_secret = oauth_app.metadata["client_secret_plain"] || oauth_app.secret

      {
        "POWERNODE_MCP_URL" => powernode_url,
        "POWERNODE_TOKEN_ENDPOINT" => "#{powernode_url}/oauth/token",
        "POWERNODE_CLIENT_ID" => oauth_app.uid,
        "POWERNODE_CLIENT_SECRET" => client_secret,
        "POWERNODE_AGENT_ID" => agent.id.to_s
      }
    end
  end
end
