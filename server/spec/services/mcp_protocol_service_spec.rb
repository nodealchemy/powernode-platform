# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::ProtocolService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#initialize' do
    it 'initializes with default protocol version' do
      expect(service.instance_variable_get(:@protocol_version)).to eq(Mcp::ProtocolService::DEFAULT_VERSION)
    end

    it 'sets up registry and transport services' do
      expect(service.instance_variable_get(:@registry)).to be_a(Mcp::RegistryService)
      expect(service.instance_variable_get(:@transport)).to be_a(Mcp::TransportService)
    end
  end

  describe '#handle_ping' do
    it 'returns pong response with timestamp' do
      result = service.handle_ping

      expect(result).to include(
        'pong' => true,
        'timestamp' => be_a(String),
        'server_info' => include('name' => 'Powernode MCP Server')
      )
    end
  end

  describe '#list_tools' do
    let(:ai_provider) { create(:ai_provider, account: account, provider_type: 'openai', capabilities: [ 'text_generation', 'chat' ]) }
    let!(:agent) { create(:ai_agent, account: account, provider: ai_provider, agent_type: 'assistant') }

    before do
      # Create credentials for the provider
      create(:ai_provider_credential,
             provider: ai_provider,
             account: account,
             credentials: { 'api_key' => 'test-key-123' },
             is_active: true)
    end

    before do
      # Register the agent as an MCP tool
      service.instance_variable_get(:@registry).register_tool(
        agent.mcp_tool_manifest['name'],
        agent.mcp_tool_manifest
      )
    end

    it 'returns available tools' do
      result = service.list_tools

      expect(result).to include('tools' => be_an(Array))
      expect(result['tools']).not_to be_empty
    end

    it 'filters tools by type' do
      result = service.list_tools({ type: 'ai_agent' })

      # Formatted tools include name, description, and inputSchema (type is not exposed in discovery format)
      expect(result['tools']).to all(include('name', 'description', 'inputSchema'))
    end
  end

  describe '#describe_tool' do
    let(:ai_provider) { create(:ai_provider, account: account, provider_type: 'openai', capabilities: [ 'text_generation', 'chat' ]) }
    let!(:agent) { create(:ai_agent, account: account, provider: ai_provider, agent_type: 'assistant') }
    let(:tool_id) { agent.mcp_tool_manifest['name'] }

    before do
      # Create credentials for the provider
      create(:ai_provider_credential,
             provider: ai_provider,
             account: account,
             credentials: { 'api_key' => 'test-key-123' },
             is_active: true)

      service.instance_variable_get(:@registry).register_tool(tool_id, agent.mcp_tool_manifest)
    end

    it 'returns tool details' do
      result = service.describe_tool(tool_id)

      expect(result).to include(
        'name' => tool_id,
        'type' => 'ai_agent',
        'capabilities' => be_an(Array)
      )
    end

    it 'raises error for non-existent tool' do
      expect { service.describe_tool('non_existent') }
        .to raise_error(StandardError, /Tool not found/)
    end
  end

  describe '#invoke_tool' do
    let(:ai_provider) { create(:ai_provider, account: account, provider_type: 'openai', capabilities: [ 'text_generation', 'chat' ]) }
    let!(:agent) { create(:ai_agent, account: account, provider: ai_provider, agent_type: 'assistant') }
    let(:tool_id) { agent.mcp_tool_manifest['name'] }
    let(:params) { { 'input' => 'test input' } }
    let(:options) { { user: user } }

    before do
      # Create credentials for the provider
      create(:ai_provider_credential,
             provider: ai_provider,
             account: account,
             credentials: { 'api_key' => 'test-key-123' },
             is_active: true)

      # Ensure the manifest includes agent_id in metadata
      manifest = agent.mcp_tool_manifest
      manifest['metadata'] ||= {}
      manifest['metadata']['agent_id'] = agent.id.to_s

      service.instance_variable_get(:@registry).register_tool(tool_id, manifest)

      # Mock the agent execution to avoid actual API calls
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute).and_return({
        'output' => 'test response',
        'metadata' => {
          'tokens_used' => 42,
          'processing_time_ms' => 150,
          'model_used' => 'gpt-3.5-turbo'
        }
      })
    end

    it 'validates tool input against schema' do
      # This will test schema validation once we implement it
      expect { service.invoke_tool(tool_id, params, options) }
        .not_to raise_error
    end

    it 'includes execution context in response' do
      result = service.invoke_tool(tool_id, params, options)

      expect(result).to include(
        jsonrpc: '2.0',
        id: be_a(String),
        result: be_a(Hash)
      )
      expect(result[:result]).to include('output' => be_a(String))
    end

    # IMP-6e5b053c52d2: #invoke_tool is the live tool-invocation path for the
    # real MCP protocol traffic (routed here from
    # Api::V1::Mcp::StreamableHttpController, the actual /api/v1/mcp/message
    # endpoint) -- unlike its sibling #register_tool (down-ranked separately
    # as unreachable), this method runs on every real tool call. It only
    # calls @telemetry.track_tool_invocation_* (Mcp::TelemetryService --
    # entirely in-memory, a fresh instance per ProtocolService.new, discarded
    # at the end of the request; #persist_metric logs a line and
    # #send_to_external_monitoring is an empty stub even in production). No
    # code path anywhere writes a durable, queryable record of who invoked
    # what.
    #
    # DELIBERATE, investigated absence -- not an oversight left for later:
    #   - mcp_tool_executions.mcp_tool_id is NOT NULL, and McpTool/McpServer
    #     represent a DIFFERENT concept (an account's own externally-configured
    #     MCP server connection -- see semantic_tool_discovery_service.rb's
    #     source: "platform" vs source: "mcp_server" split); McpTool.count == 0
    #     in this DB, so the FK structurally blocks writing there for the
    #     traffic that matters.
    #   - AuditLog serializes every insert behind ONE global Postgres advisory
    #     lock to assign its SHA256 hash-chain sequence number
    #     (Audit::LogIntegrityService::SEQUENCE_LOCK_KEY) and has no retention
    #     job -- built for low-volume compliance events, not a firehose of
    #     tool calls.
    #   - This subsystem already has a write-only persistence precedent
    #     (Mcp::RegistryService's Redis keys + unreachable DB stubs, found the
    #     same night); a new table with no consumer identified would repeat it.
    # A real fix needs a purpose-built, decoupled table PLUS a reader (an
    # admin/activity view) scoped as its own piece of work -- see IMP-6e5b053c52d2.
    it 'produces no durable execution record anywhere -- documented, not accidental' do
      expect { service.invoke_tool(tool_id, params, options) }
        .to change { McpToolExecution.count }.by(0)
        .and change { AuditLog.count }.by(0)
    end
  end

  describe '#handle_initialize_request' do
    let(:client_info) do
      {
        'protocolVersion' => '2025-06-18',
        'capabilities' => {
          'tools' => { 'listChanged' => true }
        },
        'clientInfo' => {
          'name' => 'Test Client',
          'version' => '1.0.0'
        }
      }
    end

    it 'returns server capabilities' do
      result = service.handle_initialize_request(client_info)

      expect(result).to include(
        'connection_id' => be_a(String),
        'server_capabilities' => be_a(Hash),
        'available_tools' => be_a(Integer)
      )
    end

    it 'validates protocol version compatibility' do
      # Protocol version 1.0.0 is not supported
      invalid_client = client_info.merge('protocolVersion' => '1.0.0')

      expect { service.handle_initialize_request(invalid_client) }
        .to raise_error(StandardError, /Unsupported protocol version/)
    end
  end

  describe 'error handling' do
    it 'handles malformed JSON-RPC messages' do
      expect { service.send(:create_mcp_response, result: {}) }
        .not_to raise_error
    end

    it 'provides structured error responses' do
      error_response = service.send(:create_error_response, 'test_id', 'Test error', -32600)

      expect(error_response).to include(
        'jsonrpc' => '2.0',
        'id' => 'test_id',
        'error' => include(
          'code' => -32600,
          'message' => 'Test error'
        )
      )
    end
  end
end
