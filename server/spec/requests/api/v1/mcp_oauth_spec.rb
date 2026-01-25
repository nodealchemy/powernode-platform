# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::McpOauth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['mcp.servers.write']) }
  let(:headers) { auth_headers_for(user) }

  let(:mcp_server) do
    create(:mcp_server, account: account, auth_type: 'oauth2', oauth_state: SecureRandom.hex(16))
  end
  let(:oauth_service) { instance_double(Mcp::OauthService) }

  before do
    allow(Mcp::OauthService).to receive(:new).and_return(oauth_service)
  end

  describe 'POST /api/v1/mcp_servers/:id/oauth/authorize' do
    context 'with OAuth-configured server' do
      it 'generates authorization URL successfully' do
        authorization_url = 'https://oauth.example.com/authorize?client_id=123&state=abc'

        allow(oauth_service).to receive(:generate_authorization_url)
          .and_return(authorization_url)

        post "/api/v1/mcp_servers/#{mcp_server.id}/oauth/authorize", headers: headers, as: :json

        expect_success_response
        expect(json_response_data).to include(
          'authorization_url' => authorization_url,
          'state' => mcp_server.oauth_state
        )
      end

      it 'accepts custom redirect_uri parameter' do
        expect(oauth_service).to receive(:generate_authorization_url)
          .with(redirect_uri: 'https://custom.example.com/callback')
          .and_return('https://oauth.example.com/authorize')

        post "/api/v1/mcp_servers/#{mcp_server.id}/oauth/authorize",
             params: { redirect_uri: 'https://custom.example.com/callback' },
             headers: headers, as: :json

        expect_success_response
      end
    end

    context 'with non-OAuth server' do
      let(:non_oauth_server) { create(:mcp_server, account: account, auth_type: 'api_key') }

      it 'returns error' do
        post "/api/v1/mcp_servers/#{non_oauth_server.id}/oauth/authorize", headers: headers, as: :json

        expect_error_response('Server is not configured for OAuth authentication', 422)
      end
    end

    context 'with configuration error' do
      it 'returns error when OAuth configuration is invalid' do
        allow(oauth_service).to receive(:generate_authorization_url)
          .and_raise(Mcp::OauthService::ConfigurationError.new('Missing client_id'))

        post "/api/v1/mcp_servers/#{mcp_server.id}/oauth/authorize", headers: headers, as: :json

        expect_error_response('OAuth configuration error: Missing client_id', 422)
      end
    end
  end

  describe 'GET /api/v1/mcp/oauth/callback' do
    let(:code) { 'auth_code_123' }
    let(:state) { mcp_server.oauth_state }

    context 'with valid parameters' do
      it 'exchanges code for tokens successfully' do
        token_response = {
          access_token: 'token_123',
          refresh_token: 'refresh_123',
          expires_in: 3600
        }

        allow(McpServer).to receive_message_chain(:where, :where, :find_by)
          .and_return(mcp_server)
        allow(oauth_service).to receive(:exchange_code_for_tokens)
          .and_return(token_response)
        allow(mcp_server).to receive(:reload).and_return(mcp_server)
        allow(mcp_server).to receive(:oauth_connected?).and_return(true)
        allow(mcp_server).to receive(:oauth_token_expires_at).and_return(1.hour.from_now)

        get '/api/v1/mcp/oauth/callback',
            params: { code: code, state: state },
            headers: headers, as: :json

        expect_success_response
        expect(json_response_data).to include(
          'mcp_server_id' => mcp_server.id,
          'oauth_connected' => true
        )
      end
    end

    context 'with OAuth error from provider' do
      it 'returns error message' do
        get '/api/v1/mcp/oauth/callback',
            params: { error: 'access_denied', error_description: 'User denied access', state: state },
            headers: headers, as: :json

        expect_error_response('OAuth authorization failed: User denied access', 422)
      end
    end

    context 'with missing parameters' do
      it 'returns error when code is missing' do
        get '/api/v1/mcp/oauth/callback',
            params: { state: state },
            headers: headers, as: :json

        expect_error_response('Missing required OAuth parameters (code and state)', 400)
      end

      it 'returns error when state is missing' do
        get '/api/v1/mcp/oauth/callback',
            params: { code: code },
            headers: headers, as: :json

        expect_error_response('Missing required OAuth parameters (code and state)', 400)
      end
    end

    context 'with invalid state' do
      it 'returns error' do
        allow(McpServer).to receive_message_chain(:where, :where, :find_by)
          .and_return(nil)

        get '/api/v1/mcp/oauth/callback',
            params: { code: code, state: 'invalid_state' },
            headers: headers, as: :json

        expect_error_response('Invalid or expired OAuth state', 400)
      end
    end

    context 'with authorization error' do
      it 'handles authorization errors' do
        allow(McpServer).to receive_message_chain(:where, :where, :find_by)
          .and_return(mcp_server)
        allow(oauth_service).to receive(:exchange_code_for_tokens)
          .and_raise(Mcp::OauthService::AuthorizationError.new('Invalid code'))

        get '/api/v1/mcp/oauth/callback',
            params: { code: code, state: state },
            headers: headers, as: :json

        expect_error_response('OAuth authorization failed: Invalid code', 422)
      end
    end
  end

  describe 'GET /api/v1/mcp_servers/:id/oauth/status' do
    it 'returns OAuth status' do
      oauth_status = {
        connected: true,
        expires_at: 1.hour.from_now,
        has_refresh_token: true
      }
      allow(mcp_server).to receive(:oauth_status).and_return(oauth_status)

      get "/api/v1/mcp_servers/#{mcp_server.id}/oauth/status", headers: headers, as: :json

      expect_success_response
      expect(json_response_data).to include(
        'mcp_server_id' => mcp_server.id,
        'oauth_status' => oauth_status
      )
    end

    context 'with non-existent server' do
      it 'returns not found error' do
        get "/api/v1/mcp_servers/#{SecureRandom.uuid}/oauth/status", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end
  end

  describe 'DELETE /api/v1/mcp_servers/:id/oauth/disconnect' do
    let(:oauth_configured_server) do
      create(:mcp_server,
             account: account,
             auth_type: 'oauth2',
             oauth_access_token: 'token_123',
             oauth_refresh_token: 'refresh_123')
    end

    context 'with OAuth-configured server' do
      it 'disconnects OAuth successfully' do
        allow(oauth_service).to receive(:revoke_tokens!)

        delete "/api/v1/mcp_servers/#{oauth_configured_server.id}/oauth/disconnect",
               headers: headers, as: :json

        expect_success_response
        expect(json_response_data).to include(
          'oauth_connected' => false,
          'message' => 'OAuth disconnected successfully'
        )
      end
    end

    context 'with non-OAuth server' do
      let(:non_oauth_server) { create(:mcp_server, account: account, auth_type: 'api_key') }

      it 'returns error' do
        delete "/api/v1/mcp_servers/#{non_oauth_server.id}/oauth/disconnect",
               headers: headers, as: :json

        expect_error_response('Server does not have OAuth configured', 422)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/oauth/refresh' do
    let(:oauth_server_with_refresh) do
      create(:mcp_server,
             account: account,
             auth_type: 'oauth2',
             oauth_access_token: 'old_token',
             oauth_refresh_token: 'refresh_123')
    end

    context 'with valid refresh token' do
      it 'refreshes token successfully' do
        allow(oauth_service).to receive(:refresh_token!)
        allow(oauth_server_with_refresh).to receive(:reload).and_return(oauth_server_with_refresh)
        allow(oauth_server_with_refresh).to receive(:oauth_connected?).and_return(true)
        allow(oauth_server_with_refresh).to receive(:oauth_token_expires_at).and_return(1.hour.from_now)

        post "/api/v1/mcp_servers/#{oauth_server_with_refresh.id}/oauth/refresh",
             headers: headers, as: :json

        expect_success_response
        expect(json_response_data).to include(
          'oauth_connected' => true,
          'message' => 'OAuth token refreshed successfully'
        )
      end
    end

    context 'without OAuth configuration' do
      let(:non_oauth_server) { create(:mcp_server, account: account, auth_type: 'api_key') }

      it 'returns error' do
        post "/api/v1/mcp_servers/#{non_oauth_server.id}/oauth/refresh",
             headers: headers, as: :json

        expect_error_response('Server does not have OAuth configured', 422)
      end
    end

    context 'without refresh token' do
      let(:oauth_server_no_refresh) do
        create(:mcp_server,
               account: account,
               auth_type: 'oauth2',
               oauth_access_token: 'token',
               oauth_refresh_token: nil)
      end

      it 'returns error' do
        post "/api/v1/mcp_servers/#{oauth_server_no_refresh.id}/oauth/refresh",
             headers: headers, as: :json

        expect_error_response('No refresh token available', 422)
      end
    end

    context 'with token refresh error' do
      it 'handles refresh errors' do
        allow(oauth_service).to receive(:refresh_token!)
          .and_raise(Mcp::OauthService::TokenRefreshError.new('Refresh token expired'))

        post "/api/v1/mcp_servers/#{oauth_server_with_refresh.id}/oauth/refresh",
             headers: headers, as: :json

        expect_error_response('Token refresh failed: Refresh token expired', 422)
      end
    end
  end

  describe 'permissions' do
    let(:user_without_permission) { create(:user, account: account, permissions: ['mcp.servers.read']) }
    let(:no_perm_headers) { auth_headers_for(user_without_permission) }

    it 'requires mcp.servers.write permission for authorize' do
      post "/api/v1/mcp_servers/#{mcp_server.id}/oauth/authorize", headers: no_perm_headers, as: :json

      expect_error_response('Insufficient permissions to manage MCP server OAuth', 403)
    end

    it 'requires mcp.servers.write permission for disconnect' do
      delete "/api/v1/mcp_servers/#{mcp_server.id}/oauth/disconnect", headers: no_perm_headers, as: :json

      expect_error_response('Insufficient permissions to manage MCP server OAuth', 403)
    end

    it 'requires mcp.servers.write permission for refresh' do
      post "/api/v1/mcp_servers/#{mcp_server.id}/oauth/refresh", headers: no_perm_headers, as: :json

      expect_error_response('Insufficient permissions to manage MCP server OAuth', 403)
    end
  end

  describe 'authentication' do
    it 'requires authentication for all endpoints' do
      post "/api/v1/mcp_servers/#{mcp_server.id}/oauth/authorize", as: :json

      expect_error_response('Access token required', 401)
    end
  end
end
