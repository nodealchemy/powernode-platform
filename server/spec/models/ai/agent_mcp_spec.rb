# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agent, 'MCP functionality', type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ai_provider) { create(:ai_provider, account: account) }

  describe 'MCP validations' do
    subject(:agent) do
      build(:ai_agent,
            account: account,
            creator: user,
            provider: ai_provider,
            version: '1.0.0')
    end

    it { is_expected.to be_valid }

    describe 'version validation' do
      it 'requires semantic version format' do
        agent.version = '1.0'
        expect(agent).not_to be_valid
        expect(agent.errors[:version]).to include('must be in semantic version format (x.y.z)')
      end

      it 'accepts valid semantic versions' do
        %w[1.0.0 2.1.3 10.20.30].each do |version|
          agent.version = version
          expect(agent).to be_valid
        end
      end
    end

    describe 'mcp_tool_manifest validation' do
      it 'validates manifest structure' do
        agent.mcp_tool_manifest = { invalid: 'structure' }
        expect(agent).not_to be_valid
      end

      it 'accepts valid manifest structure' do
        agent.mcp_tool_manifest = {
          'name' => 'test_agent',
          'description' => 'Test agent',
          'type' => 'ai_agent',
          'version' => '1.0.0',
          'capabilities' => [ 'text_generation' ]
        }
        expect(agent).to be_valid
      end
    end
  end

  describe 'MCP methods' do
    let(:agent) do
      create(:ai_agent,
             account: account,
             creator: user,
             provider: ai_provider,
             version: '1.0.0')
    end

    describe '#mcp_available?' do
      it 'returns true when agent has MCP manifest' do
        agent.mcp_tool_manifest = {
          'name' => 'test_agent',
          'type' => 'ai_agent',
          'capabilities' => [ 'text_generation' ]
        }
        expect(agent.mcp_available?).to be true
      end

      it 'returns false when agent has no MCP manifest' do
        agent.mcp_tool_manifest = {}
        expect(agent.mcp_available?).to be false
      end

      it 'returns false when agent is inactive' do
        agent.status = 'inactive'
        expect(agent.mcp_available?).to be false
      end
    end

    describe '#generate_mcp_tool_manifest' do
      it 'generates a valid MCP tool manifest' do
        manifest = agent.generate_mcp_tool_manifest

        expect(manifest).to include(
          'name' => be_a(String),
          'description' => agent.description,
          'type' => 'ai_agent',
          'version' => agent.version,
          'capabilities' => agent.skill_slugs
        )
      end

      it 'includes input and output schemas' do
        manifest = agent.generate_mcp_tool_manifest

        expect(manifest).to include(
          'inputSchema' => be_a(Hash),
          'outputSchema' => be_a(Hash)
        )
      end

      it 'normalizes agent name for tool ID' do
        agent.name = 'Test Agent With Spaces!'
        manifest = agent.generate_mcp_tool_manifest

        expect(manifest['name']).to match(/^[a-z0-9_]+$/)
      end
    end

    describe '#execute_via_mcp' do
      let(:input_parameters) { { 'input' => 'test input' } }
      let(:execution_options) { { user: user } }

      before do
        agent.update!(
          mcp_tool_manifest: {
            'name' => 'test_agent',
            'description' => 'Test agent for MCP',
            'type' => 'ai_agent',
            'version' => '1.0.0',
            'capabilities' => [ 'text_generation' ]
          }
        )
      end

      it 'raises error when agent not available for MCP' do
        agent.update!(status: 'inactive')

        expect { agent.execute_via_mcp(input_parameters, execution_options) }
          .to raise_error(StandardError, /Agent not available for MCP execution/)
      end

      it 'creates an MCP execution record' do
        allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute).and_return({
          'execution_id' => 'test_123',
          'status' => 'completed'
        })

        expect { agent.execute_via_mcp(input_parameters, execution_options) }
          .to change(Ai::AgentExecution, :count).by(1)
      end

      it 'returns execution result' do
        allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute).and_return({
          'execution_id' => 'test_123',
          'status' => 'completed',
          'result' => 'test output'
        })

        result = agent.execute_via_mcp(input_parameters, execution_options)

        expect(result).to include(
          'execution_id' => 'test_123',
          'status' => 'completed',
          'result' => 'test output'
        )
      end
    end

    describe '#validate_mcp_input' do
      it 'validates input against MCP input schema' do
        agent.mcp_input_schema = {
          'type' => 'object',
          'properties' => {
            'input' => { 'type' => 'string' }
          },
          'required' => [ 'input' ]
        }

        expect(agent.validate_mcp_input({ 'input' => 'test' })).to be true
        expect(agent.validate_mcp_input({})).to be false
      end
    end

    describe '#validate_mcp_output' do
      it 'validates output against MCP output schema' do
        agent.mcp_output_schema = {
          'type' => 'object',
          'properties' => {
            'result' => { 'type' => 'string' }
          },
          'required' => [ 'result' ]
        }

        expect(agent.validate_mcp_output({ 'result' => 'test' })).to be true
        expect(agent.validate_mcp_output({})).to be false
      end
    end
  end

  describe 'MCP lifecycle callbacks' do
    let(:agent) { build(:ai_agent, account: account, creator: user, provider: ai_provider) }

    it 'generates MCP manifest after creation' do
      agent.save!

      expect(agent.mcp_tool_manifest).not_to be_empty
      expect(agent.mcp_tool_manifest['name']).to be_present
    end

    it 'updates MCP registration timestamp' do
      agent.save!

      expect(agent.mcp_registered_at).to be_within(1.second).of(Time.current)
    end

    it 'regenerates manifest when name changes' do
      agent.save!
      original_manifest = agent.mcp_tool_manifest.dup

      agent.update!(name: 'New Agent Name')

      expect(agent.mcp_tool_manifest['name']).not_to eq(original_manifest['name'])
    end
  end

  describe 'MCP scopes' do
    let!(:mcp_agent) do
      create(:ai_agent,
             account: account,
             creator: user,
             provider: ai_provider)
    end

    let!(:non_mcp_agent) do
      agent = create(:ai_agent,
             account: account,
             creator: user,
             provider: ai_provider)
      agent.update_column(:mcp_tool_manifest, {})  # Force empty manifest
      agent
    end

    describe '.mcp_enabled' do
      it 'returns only agents with MCP manifests' do
        results = Ai::Agent.mcp_enabled

        expect(results).to include(mcp_agent)
        expect(results).not_to include(non_mcp_agent)
      end
    end
  end

  describe 'MCP API enforcement' do
    let!(:agent) { create(:ai_agent, account: account, creator: user, provider: ai_provider) }

    it 'uses skill_slugs for capability queries' do
      expect(agent.skill_slugs).to be_an(Array)
    end

    it 'uses mcp_metadata for configuration' do
      expect(agent.mcp_metadata).to be_a(Hash)
    end

    it 'uses mcp_tool_manifest for tool registration' do
      expect(agent.mcp_tool_manifest).to be_a(Hash)
      expect(agent.mcp_tool_manifest['name']).to be_present
    end
  end
end
