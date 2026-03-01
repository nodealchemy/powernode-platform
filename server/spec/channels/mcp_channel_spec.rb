# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) do
    user = create(:user, account: account)
    # Create a role with MCP permissions
    role = Role.find_or_create_by(name: 'mcp_user') do |r|
      r.display_name = 'MCP User'
      r.description = 'User with MCP access permissions'
      r.role_type = 'user'
      r.is_system = false
      r.immutable = false
    end

    # Add the required permissions to the role
    role.add_permission('ai.agents.read')
    role.add_permission('ai.workflows.read')

    # Assign the role to the user
    user.user_roles.create!(role: role)
    user
  end
  let!(:ai_agent) { create(:ai_agent, account: account, agent_type: 'assistant') }

  before do
    stub_connection current_user: user
  end

  describe 'subscription' do
    context 'with valid user and permissions' do
      it 'successfully subscribes to MCP channel' do
        subscribe

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_for("mcp_account_#{account.id}")
        expect(subscription).to have_stream_for("mcp_user_#{user.id}")
        expect(subscription).to have_stream_for("mcp_tools_#{account.id}")
      end

      it 'sends initialization response' do
        subscribe

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'method' => 'initialized',
          'params' => include(
            'connection_id' => be_a(String),
            'server_capabilities' => be_a(Hash),
            'account_id' => account.id
          )
        )
      end
    end

    context 'without required permissions' do
      let(:user) do
        user = create(:user, account: account)
        # Remove all roles to ensure no permissions
        user.user_roles.destroy_all
        user.reload
        user
      end

      it 'rejects subscription' do
        subscribe

        expect(subscription).to be_rejected
      end
    end

    context 'without authentication' do
      before do
        stub_connection current_user: nil
      end

      it 'rejects subscription' do
        subscribe

        expect(subscription).to be_rejected
      end
    end
  end

  describe 'MCP protocol message handling' do
    before { subscribe }

    describe '#list_tools' do
      let(:message) do
        {
          'jsonrpc' => '2.0',
          'id' => 'test_1',
          'method' => 'list_tools',
          'params' => {}
        }
      end

      it 'handles tool list requests' do
        perform :list_tools, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_1',
          'result' => include('tools' => be_an(Array))
        )
      end
    end

    describe '#describe_tool' do
      let(:message) do
        {
          'jsonrpc' => '2.0',
          'id' => 'test_2',
          'method' => 'describe_tool',
          'params' => { 'name' => ai_agent.mcp_tool_manifest['name'] }
        }
      end

      it 'handles tool description requests' do
        perform :describe_tool, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_2',
          'result' => include(
            'name' => ai_agent.mcp_tool_manifest['name'],
            'type' => 'ai_agent'
          )
        )
      end

      it 'handles missing tool name' do
        message['params'] = {}
        perform :describe_tool, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_2',
          'error' => include('message' => 'Missing tool name')
        )
      end
    end

    describe '#execute_agent' do
      let(:message) do
        {
          'jsonrpc' => '2.0',
          'id' => 'test_3',
          'method' => 'execute_agent',
          'params' => {
            'agent_id' => ai_agent.id,
            'input_parameters' => { 'input' => 'test input' }
          }
        }
      end

      it 'handles agent execution requests' do
        allow_any_instance_of(Ai::Agent).to receive(:execute_via_mcp).and_return({
          'execution_id' => 'test_exec_123',
          'status' => 'completed',
          'result' => 'test output'
        })

        perform :execute_agent, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_3',
          'result' => include(
            'execution_id' => 'test_exec_123',
            'status' => 'completed'
          )
        )
      end

      it 'handles agent not found' do
        message['params']['agent_id'] = 'non_existent'
        perform :execute_agent, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_3',
          'error' => include('message' => 'Agent not found')
        )
      end
    end

    describe '#ping' do
      let(:message) do
        {
          'jsonrpc' => '2.0',
          'id' => 'test_4',
          'method' => 'ping',
          'params' => {}
        }
      end

      it 'handles ping requests' do
        perform :ping, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_4',
          'result' => include(
            'pong' => true,
            'timestamp' => be_a(String),
            'server_info' => include('name' => 'Powernode MCP Server')
          )
        )
      end
    end

    describe '#subscribe_to_resource' do
      let(:message) do
        {
          'jsonrpc' => '2.0',
          'id' => 'test_5',
          'method' => 'subscribe_to_resource',
          'params' => {
            'resource_type' => 'tool_events',
            'resource_id' => 'all'
          }
        }
      end

      it 'handles resource subscription requests' do
        perform :subscribe_to_resource, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_5',
          'result' => include(
            'subscribed' => true,
            'resource_type' => 'tool_events',
            'resource_id' => 'all'
          )
        )
      end

      it 'handles unknown resource types' do
        message['params']['resource_type'] = 'unknown_type'
        perform :subscribe_to_resource, message

        expect(transmissions.last).to include(
          'jsonrpc' => '2.0',
          'id' => 'test_5',
          'error' => include('message' => /Unknown resource type/)
        )
      end
    end
  end

  describe 'error handling' do
    before { subscribe }

    it 'handles malformed JSON-RPC messages gracefully' do
      message = { 'invalid' => 'message' }

      expect { perform :list_tools, message }.not_to raise_error
    end

    it 'provides proper error codes for different error types' do
      # Test authorization error by removing user roles
      user.user_roles.destroy_all
      message = {
        'jsonrpc' => '2.0',
        'id' => 'test_auth',
        'method' => 'execute_agent',
        'params' => { 'agent_id' => ai_agent.id }
      }

      perform :execute_agent, message

      expect(transmissions.last).to include(
        'error' => include('code' => be_a(Integer))
      )
    end
  end

  describe 'broadcasting' do
    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

    it 'broadcasts tool events correctly' do
      McpChannel.broadcast_tool_event('registered', 'test_tool', { status: 'active' }, account)

      # Verify broadcast was sent to the tool-specific stream
      expect(ActionCable.server).to have_received(:broadcast).with(
        "mcp:mcp_tool_test_tool_events",
        include(jsonrpc: '2.0', method: 'notification')
      )
    end
  end
end
