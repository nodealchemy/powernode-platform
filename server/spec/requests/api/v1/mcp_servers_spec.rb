# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::McpServers', type: :request do
  # IMP-80e613fb9c43: for_workflow_builder (and its serializer,
  # serialize_for_workflow_builder) returned the raw McpServer#capabilities
  # hash — config secrets, last_error, allow_network,
  # allow_extended_commands, strict_environment, egress_allowlist — to any
  # account user with mcp.servers.read. It was never routed (confirmed via
  # `rails routes`, a repo-wide grep across server/worker/frontend/
  # extensions, and no dynamic dispatch by name), so nothing could reach it
  # over HTTP. NO LEGACY: deleted on discovery rather than fixed in place —
  # mirrors git/providers_spec.rb's own "the deleted ... endpoint" pattern
  # for the same class of dead, unroutable action.
  describe 'the deleted for_workflow_builder endpoint' do
    let(:workflow_builder_path) { '/api/v1/mcp_servers/for_workflow_builder' }

    # NOT a RoutingError: `resources :mcp_servers` already declares the
    # implicit `GET /:id` (show) route, so this path resolves — just to
    # `show` with id: "for_workflow_builder" (a 404-via-RecordNotFound at
    # request time, never the dead action) — since for_workflow_builder was
    # never added to a `collection do` block. The real guarantee is that
    # this path was NEVER dispatched to the for_workflow_builder action.
    it 'resolves to #show (id: "for_workflow_builder"), never to the for_workflow_builder action' do
      recognized = Rails.application.routes.recognize_path(workflow_builder_path, method: :get)
      expect(recognized).to eq(controller: 'api/v1/mcp_servers', action: 'show', id: 'for_workflow_builder')
    end

    it 'returns not-found at request time, confirming no server ever named "for_workflow_builder" leaks anything' do
      get workflow_builder_path, headers: auth_headers_for(create(:user, :manager, account: create(:account))), as: :json

      expect_error_response('MCP server not found', 404)
    end

    it 'has no controller action or serializer behind it' do
      expect(Api::V1::McpServersController.action_methods).not_to include('for_workflow_builder')
      expect(Api::V1::McpServersController.private_instance_methods).not_to include(
        :serialize_for_workflow_builder, :extract_resources_from_capabilities, :extract_prompts_from_capabilities
      )
    end
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, :manager, account: other_account) }
  let(:limited_user) { create(:user, :member, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/mcp_servers' do
    let!(:server1) { create(:mcp_server, :connected, account: account) }
    let!(:server2) { create(:mcp_server, :disconnected, account: account) }
    let!(:other_server) { create(:mcp_server, :connected, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of mcp servers for current account' do
        get '/api/v1/mcp_servers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_servers']).to be_an(Array)
        expect(data['mcp_servers'].length).to eq(2)
        expect(data['mcp_servers'].none? { |s| s['id'] == other_server.id }).to be true
        expect(data['meta']).to include('total' => 2)
        expect(data['meta']).to have_key('connected_count')
        expect(data['meta']).to have_key('disconnected_count')
        expect(data['meta']).to have_key('error_count')
      end

      it 'filters by status' do
        get '/api/v1/mcp_servers', params: { status: 'connected' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['mcp_servers'].length).to eq(1)
        expect(data['mcp_servers'].first['status']).to eq('connected')
      end

      it 'filters by connection_type' do
        stdio_server = create(:mcp_server, :stdio, account: account)

        get '/api/v1/mcp_servers', params: { connection_type: 'stdio' }, headers: headers

        expect_success_response
        data = json_response_data
        # All servers created by default have stdio connection_type, so we expect 3 total
        # (server1, server2, and stdio_server all have connection_type: 'stdio')
        expect(data['mcp_servers'].all? { |s| s['connection_type'] == 'stdio' }).to be true
      end
    end

    context 'without mcp.servers.read permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        get '/api/v1/mcp_servers', headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to view MCP servers', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/mcp_servers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/mcp_servers/:id' do
    let(:server) { create(:mcp_server, :connected, account: account) }
    let(:other_server) { create(:mcp_server, :connected, account: other_account) }

    before do
      create_list(:mcp_tool, 3, mcp_server: server)
    end

    context 'with proper permissions' do
      it 'returns mcp server details with tools' do
        get "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server']).to include(
          'id' => server.id,
          'name' => server.name,
          'status' => 'connected',
          'tools_count' => 3
        )
        expect(data['mcp_server']).to have_key('tools')
        expect(data['mcp_server']['tools']).to be_an(Array)
      end

      it 'returns not found for non-existent server' do
        get "/api/v1/mcp_servers/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end

    context 'accessing server from different account' do
      it 'returns not found error' do
        get "/api/v1/mcp_servers/#{other_server.id}", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers' do
    let(:valid_params) do
      {
        mcp_server: {
          name: 'Test MCP Server',
          description: 'A test server',
          connection_type: 'stdio',
          command: 'npx',
          args: [ '-y', '@modelcontextprotocol/server-test' ],
          config: { version: '1.0' }
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new mcp server' do
        expect {
          post '/api/v1/mcp_servers', params: valid_params, headers: headers, as: :json
        }.to change { account.mcp_servers.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['mcp_server']).to include(
          'name' => 'Test MCP Server',
          'connection_type' => 'stdio',
          'status' => 'disconnected'
        )
        expect(data['message']).to eq('MCP server created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(mcp_server: { name: nil })

        post '/api/v1/mcp_servers', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post '/api/v1/mcp_servers', params: valid_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end

    # IMP-80e613fb9c43: config is an unstructured jsonb hash with no schema
    # of its own (permit(config: {})), so it is exactly where a caller could
    # smuggle secret-shaped content that then round-trips in full via
    # serialize_mcp_server. Reject anything outside the allowlist at write
    # time so the serializer never has hidden content to filter.
    context 'with an unsupported config key' do
      it 'rejects the request with 422 naming the key and creates nothing' do
        malicious_params = valid_params.deep_merge(mcp_server: { config: { secret_token: 'shh' } })

        expect {
          post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json
        }.not_to change { account.mcp_servers.count }

        expect_error_response('secret_token', 422)
      end
    end

    # IMP-80e613fb9c43 review round 2 (BLOCKER): validate_config_keys must
    # not assume `config` or `mcp_server` are objects — malformed shapes
    # 422, never 500.
    context 'with a malformed payload' do
      it 'returns 422, not 500, when config is a string' do
        malformed = valid_params.deep_merge(mcp_server: { config: 'oops' })

        post '/api/v1/mcp_servers', params: malformed, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422, not 500, when config is an array' do
        malformed = valid_params.deep_merge(mcp_server: { config: [ 'oops' ] })

        post '/api/v1/mcp_servers', params: malformed, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422, not 500, when mcp_server itself is a scalar' do
        post '/api/v1/mcp_servers', params: { mcp_server: 'oops' }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    # IMP-80e613fb9c43 review round 2: config.capabilities/config.metadata
    # are nested unstructured hashes too — allowlist their keys AND value
    # types (capabilities: booleans only; metadata: strings only), the same
    # way the top-level allowlist covers config itself.
    context 'with an unsupported nested capabilities/metadata key or type' do
      it 'rejects an unknown capabilities key' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { capabilities: { tools: true, admin_override: true } } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('capabilities.admin_override', 422)
      end

      it 'rejects a non-boolean value on an otherwise-allowed capabilities key' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { capabilities: { tools: 'not-a-boolean' } } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('capabilities.tools', 422)
      end

      it 'rejects an unknown metadata key' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { metadata: { author: 'Acme', api_token: 'shh' } } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('metadata.api_token', 422)
      end

      it 'rejects a non-string value on an otherwise-allowed metadata key, e.g. a nested object smuggling extra content' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { metadata: { author: { name: 'Acme', token: 'shh' } } } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('metadata.author', 422)
      end
    end

    # IMP-80e613fb9c43 review round 4: version/protocol_version/
    # resources_count/prompts_count accepted ANY value — only their KEY
    # NAME was checked, never their type — so `config: { version: {
    # "api_key" => "..." } }` passed the allowlist, was stored, and
    # round-tripped back out in full.
    context 'with a wrong-typed value on an otherwise-allowed scalar config key' do
      it 'rejects a nested hash under version' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { version: { api_key: 'shh' } } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('version', 422)
      end

      it 'rejects a non-string protocol_version' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { protocol_version: 12 } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('protocol_version', 422)
      end

      it 'rejects a non-integer resources_count, including an integer-looking string (strict, no coercion)' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { resources_count: '3' } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('resources_count', 422)
      end

      it 'rejects a non-integer prompts_count' do
        malicious_params = valid_params.deep_merge(
          mcp_server: { config: { prompts_count: [ 1 ] } }
        )

        post '/api/v1/mcp_servers', params: malicious_params, headers: headers, as: :json

        expect_error_response('prompts_count', 422)
      end
    end
  end

  describe 'PATCH /api/v1/mcp_servers/:id' do
    let(:server) { create(:mcp_server, :disconnected, account: account) }
    let(:update_params) do
      {
        mcp_server: {
          name: 'Updated Server Name',
          description: 'Updated description'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the mcp server' do
        patch "/api/v1/mcp_servers/#{server.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server']['name']).to eq('Updated Server Name')
        expect(data['mcp_server']['description']).to eq('Updated description')
        expect(data['message']).to eq('MCP server updated successfully')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { mcp_server: { connection_type: 'invalid' } }

        patch "/api/v1/mcp_servers/#{server.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        patch "/api/v1/mcp_servers/#{server.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end

    # IMP-80e613fb9c43
    context 'with an unsupported config key' do
      before { server.update_column(:capabilities, server.capabilities.merge('config' => { 'version' => '1.0' })) }

      it 'rejects the request with 422 naming the key and leaves stored config untouched' do
        malicious_params = { mcp_server: { config: { api_secret: 'shh' } } }

        patch "/api/v1/mcp_servers/#{server.id}", params: malicious_params, headers: headers, as: :json

        expect_error_response('api_secret', 422)
        expect(server.reload.config).to eq('version' => '1.0')
      end
    end

    # IMP-80e613fb9c43 review round 2 (BLOCKER)
    context 'with a malformed payload' do
      it 'returns 422, not 500, when config is a string' do
        patch "/api/v1/mcp_servers/#{server.id}", params: { mcp_server: { config: 'oops' } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422, not 500, when config is an array' do
        patch "/api/v1/mcp_servers/#{server.id}", params: { mcp_server: { config: [ 'oops' ] } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422, not 500, when mcp_server itself is a scalar' do
        patch "/api/v1/mcp_servers/#{server.id}", params: { mcp_server: 'oops' }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # IMP-80e613fb9c43: config is allowlisted on BOTH sides — nothing outside
  # the allowlist can be stored through this controller (see the "unsupported
  # config key" contexts above), and the serializer defensively slices too,
  # in case a row was seeded directly in the DB (e.g. by a worker/internal
  # path, or pre-existing data from before this fix).
  describe 'config allowlisting' do
    let(:server) { create(:mcp_server, :disconnected, account: account) }

    it 'round-trips allowlisted config keys on create' do
      params = {
        mcp_server: {
          name: 'Allowlist Test Server',
          connection_type: 'stdio',
          command: 'node',
          config: {
            version: '1.0.0',
            protocol_version: '2024-11-05',
            capabilities: { tools: true, resources: true, prompts: false, logging: false },
            resources_count: 3,
            prompts_count: 1,
            metadata: { author: 'Acme', url: 'https://example.com' }
          }
        }
      }

      post '/api/v1/mcp_servers', params: params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      config = json_response_data['mcp_server']['config']
      expect(config).to include(
        'version' => '1.0.0',
        'protocol_version' => '2024-11-05',
        'resources_count' => 3,
        'prompts_count' => 1
      )
      expect(config['metadata']).to eq('author' => 'Acme', 'url' => 'https://example.com')
    end

    it 'never exposes a non-allowlisted key on show/index, even if seeded directly in the DB' do
      server.update_column(
        :capabilities,
        server.capabilities.merge('config' => { 'version' => '1.0', 'oauth_client_secret' => 'topsecret' })
      )

      get "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json

      expect_success_response
      config = json_response_data['mcp_server']['config']
      expect(config).to eq('version' => '1.0')
      expect(config).not_to have_key('oauth_client_secret')

      get '/api/v1/mcp_servers', headers: headers, as: :json

      expect_success_response
      index_config = json_response_data['mcp_servers'].find { |s| s['id'] == server.id }['config']
      expect(index_config).to eq('version' => '1.0')
    end

    it 'strips non-allowlisted nested capabilities/metadata content seeded directly in the DB' do
      server.update_column(
        :capabilities,
        server.capabilities.merge(
          'config' => {
            'version' => '1.0',
            'capabilities' => { 'tools' => true, 'admin_override' => true },
            'metadata' => { 'author' => 'Acme', 'internal_note' => 'shh', 'url' => { 'nested' => 'object' } }
          }
        )
      )

      get "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json

      expect_success_response
      config = json_response_data['mcp_server']['config']
      expect(config['capabilities']).to eq('tools' => true)
      expect(config['metadata']).to eq('author' => 'Acme')
    end

    it 'never returns a wrong-typed scalar config value seeded directly in the DB' do
      server.update_column(
        :capabilities,
        server.capabilities.merge(
          'config' => {
            'version' => { 'api_key' => 'shh' },
            'protocol_version' => '2024-11-05',
            'resources_count' => '3',
            'prompts_count' => 1
          }
        )
      )

      get "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json

      expect_success_response
      config = json_response_data['mcp_server']['config']
      expect(config).not_to have_key('version')
      expect(config).not_to have_key('resources_count')
      expect(config).to include('protocol_version' => '2024-11-05', 'prompts_count' => 1)
    end
  end

  describe 'DELETE /api/v1/mcp_servers/:id' do
    let!(:server) { create(:mcp_server, :disconnected, account: account) }

    context 'with proper permissions' do
      it 'deletes the mcp server' do
        expect {
          delete "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json
        }.to change { account.mcp_servers.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('MCP server deleted successfully')
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        delete "/api/v1/mcp_servers/#{server.id}", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/connect' do
    let(:server) { create(:mcp_server, :disconnected, account: account) }

    context 'with proper permissions' do
      it 'connects to the mcp server' do
        allow_any_instance_of(McpServer).to receive(:connect!).and_return(true)

        post "/api/v1/mcp_servers/#{server.id}/connect", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('MCP server connected successfully')
      end

      it 'returns error when connection fails' do
        allow_any_instance_of(McpServer).to receive(:connect!).and_raise(StandardError, 'Connection failed')

        post "/api/v1/mcp_servers/#{server.id}/connect", headers: headers, as: :json

        expect_error_response('Failed to connect: Connection failed', 422)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/disconnect' do
    let(:server) { create(:mcp_server, :connected, account: account) }

    context 'with proper permissions' do
      it 'disconnects from the mcp server' do
        allow_any_instance_of(McpServer).to receive(:disconnect!).and_return(true)

        post "/api/v1/mcp_servers/#{server.id}/disconnect", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('MCP server disconnected successfully')
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/health_check' do
    let(:server) { create(:mcp_server, :connected, account: account) }

    context 'with proper permissions' do
      it 'performs health check' do
        post "/api/v1/mcp_servers/#{server.id}/health_check", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server_id']).to eq(server.id)
        expect(data['healthy']).to be true
        expect(data).to have_key('checked_at')
      end
    end

    context 'without mcp.servers.read permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post "/api/v1/mcp_servers/#{server.id}/health_check", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to view MCP servers', 403)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/discover_tools' do
    let(:server) { create(:mcp_server, :connected, account: account) }

    context 'with proper permissions' do
      it 'discovers tools from the server' do
        tools = create_list(:mcp_tool, 3, mcp_server: server)
        allow_any_instance_of(McpServer).to receive(:discover_tools).and_return(tools)

        post "/api/v1/mcp_servers/#{server.id}/discover_tools", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server_id']).to eq(server.id)
        expect(data['tools_discovered']).to eq(3)
        expect(data['tools']).to be_an(Array)
        expect(data['message']).to eq('Discovered 3 tools')
      end

      it 'returns error when discovery fails' do
        allow_any_instance_of(McpServer).to receive(:discover_tools).and_raise(StandardError, 'Discovery failed')

        post "/api/v1/mcp_servers/#{server.id}/discover_tools", headers: headers, as: :json

        expect_error_response('Failed to discover tools: Discovery failed', 422)
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post "/api/v1/mcp_servers/#{server.id}/discover_tools", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end
  end
end
