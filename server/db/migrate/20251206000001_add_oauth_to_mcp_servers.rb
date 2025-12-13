# frozen_string_literal: true

class AddOauthToMcpServers < ActiveRecord::Migration[8.0]
  def change
    # Authentication type: none, api_key, or oauth2
    add_column :mcp_servers, :auth_type, :string, default: 'none', null: false

    # OAuth provider name (e.g., 'github', 'google', 'slack')
    add_column :mcp_servers, :oauth_provider, :string

    # OAuth client credentials (client_id is not encrypted, client_secret is)
    add_column :mcp_servers, :oauth_client_id, :string
    add_column :mcp_servers, :oauth_client_secret_encrypted, :text

    # OAuth endpoints
    add_column :mcp_servers, :oauth_authorization_url, :string
    add_column :mcp_servers, :oauth_token_url, :string
    add_column :mcp_servers, :oauth_scopes, :string

    # OAuth tokens (encrypted)
    add_column :mcp_servers, :oauth_access_token_encrypted, :text
    add_column :mcp_servers, :oauth_refresh_token_encrypted, :text
    add_column :mcp_servers, :oauth_token_expires_at, :datetime
    add_column :mcp_servers, :oauth_token_type, :string, default: 'Bearer'

    # OAuth PKCE and CSRF protection
    add_column :mcp_servers, :oauth_pkce_code_verifier, :string
    add_column :mcp_servers, :oauth_state, :string

    # OAuth metadata
    add_column :mcp_servers, :oauth_last_refreshed_at, :datetime
    add_column :mcp_servers, :oauth_error, :text

    # Indexes
    add_index :mcp_servers, :auth_type
    add_index :mcp_servers, :oauth_state, unique: true, where: "oauth_state IS NOT NULL"
    add_index :mcp_servers, :oauth_token_expires_at
  end
end
