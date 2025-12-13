# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowNode, type: :model do
  describe 'associations' do
    it { should belong_to(:ai_workflow) }
    it { should have_many(:ai_workflow_node_executions).dependent(:destroy) }
    it { should have_many(:source_edges).class_name('AiWorkflowEdge').with_foreign_key('source_node_id').with_primary_key('node_id') }
    it { should have_many(:target_edges).class_name('AiWorkflowEdge').with_foreign_key('target_node_id').with_primary_key('node_id') }
  end

  describe 'validations' do
    subject { build(:ai_workflow_node) }

    it { should validate_presence_of(:node_id) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:node_type) }
    it { should validate_presence_of(:position) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_numericality_of(:timeout_seconds).is_greater_than(0) }
    it { should validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0) }

    it 'validates inclusion of node_type' do
      # Test a few representative types - the full list is in the model
      valid_types = %w[ai_agent api_call condition]

      valid_types.each do |type|
        node = build(:ai_workflow_node, type.to_sym)
        expect(node).to be_valid, "Expected #{type} to be valid but got errors: #{node.errors.full_messages.join(', ')}"
      end
    end

    it 'rejects invalid node_type' do
      node = build(:ai_workflow_node, node_type: 'invalid_type')
      expect(node).not_to be_valid
      expect(node.errors[:node_type]).to include('must be a valid node type')
    end

    context 'node_id uniqueness' do
      let!(:existing_node) { create(:ai_workflow_node) }

      it 'validates uniqueness of node_id within workflow scope' do
        duplicate_node = build(:ai_workflow_node,
                              node_id: existing_node.node_id,
                              ai_workflow: existing_node.ai_workflow)

        expect(duplicate_node).not_to be_valid
        expect(duplicate_node.errors[:node_id]).to include('has already been taken')
      end

      it 'allows same node_id in different workflows' do
        different_workflow = create(:ai_workflow)
        node_with_same_id = build(:ai_workflow_node,
                                 node_id: existing_node.node_id,
                                 ai_workflow: different_workflow)

        expect(node_with_same_id).to be_valid
      end
    end

    context 'configuration validation' do
      context 'ai_agent node type' do
        it 'requires agent_id in configuration' do
          workflow = create(:ai_workflow)
          node = build(:ai_workflow_node, node_type: 'ai_agent', ai_workflow: workflow)
          node.configuration = node.configuration.merge('agent_id' => nil)

          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify an agent_id for AI agent nodes')
        end

        it 'validates agent_id exists' do
          workflow = create(:ai_workflow)
          node = build(:ai_workflow_node, node_type: 'ai_agent', ai_workflow: workflow)
          node.configuration = node.configuration.merge('agent_id' => SecureRandom.uuid)

          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('specified agent_id does not exist')
        end
      end

      context 'api_call node type' do
        let(:node) { build(:ai_workflow_node, :api_call) }

        it 'requires url in configuration' do
          node.configuration = node.configuration.merge('url' => '')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify a URL for API call nodes')
        end

        it 'validates HTTP method' do
          node.configuration = node.configuration.merge('method' => 'INVALID')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify a valid HTTP method')
        end
      end

      context 'webhook node type' do
        let(:node) { build(:ai_workflow_node, :webhook) }

        it 'requires url in configuration' do
          node.configuration = node.configuration.merge('url' => '')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify a URL for webhook nodes')
        end
      end

      context 'condition node type' do
        let(:node) { build(:ai_workflow_node, :condition) }

        it 'requires conditions array in configuration' do
          node.configuration = node.configuration.merge('conditions' => nil)
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify conditions array for condition nodes')
        end
      end

      context 'loop node type' do
        let(:node) { build(:ai_workflow_node, :loop) }

        it 'requires iteration_source in configuration' do
          node.configuration = node.configuration.merge('iteration_source' => '')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify iteration_source for loop nodes')
        end

        it 'validates max_iterations is a positive integer' do
          node.configuration = node.configuration.merge('max_iterations' => -1)
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('max_iterations must be a positive integer')
        end
      end

      context 'delay node type' do
        let(:node) { build(:ai_workflow_node, :delay) }

        it 'validates delay_seconds for fixed delays' do
          node.configuration = {
            'delay_type' => 'fixed',
            'delay_seconds' => -5
          }
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('delay_seconds must be a positive integer for fixed delays')
        end
      end

      context 'human_approval node type' do
        let(:node) { build(:ai_workflow_node, :human_approval) }

        it 'requires approvers array in configuration' do
          node.configuration = node.configuration.merge('approvers' => nil)
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify approvers array for human approval nodes')
        end
      end

      context 'sub_workflow node type' do
        let(:workflow) { create(:ai_workflow) }
        let(:node) { build(:ai_workflow_node, :sub_workflow, ai_workflow: workflow) }

        it 'requires workflow_id in configuration' do
          node.configuration = node.configuration.merge('workflow_id' => nil)
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify workflow_id for sub-workflow nodes')
        end

        it 'validates workflow_id exists' do
          node.configuration = node.configuration.merge('workflow_id' => SecureRandom.uuid)
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('specified workflow_id does not exist')
        end
      end

      # Consolidated Node Types (Phase 1A)
      context 'kb_article node type' do
        let(:node) { build(:ai_workflow_node, :kb_article) }

        it 'validates valid actions' do
          %w[create read update search publish].each do |action|
            node.configuration = node.configuration.merge('action' => action)
            node.valid?
            expect(node.errors[:configuration]).not_to include('action must be one of: create, read, update, search, publish')
          end
        end

        it 'rejects invalid action' do
          node.configuration = node.configuration.merge('action' => 'invalid_action')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('action must be one of: create, read, update, search, publish')
        end

        it 'requires action in configuration' do
          node.configuration = node.configuration.except('action')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('action must be one of: create, read, update, search, publish')
        end
      end

      context 'page node type' do
        let(:node) { build(:ai_workflow_node, :page) }

        it 'validates valid actions' do
          %w[create read update publish].each do |action|
            node.configuration = node.configuration.merge('action' => action)
            node.valid?
            expect(node.errors[:configuration]).not_to include('action must be one of: create, read, update, publish')
          end
        end

        it 'rejects invalid action' do
          node.configuration = node.configuration.merge('action' => 'delete')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('action must be one of: create, read, update, publish')
        end

        it 'requires action in configuration' do
          node.configuration = node.configuration.except('action')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('action must be one of: create, read, update, publish')
        end
      end

      context 'mcp_operation node type' do
        let(:node) { build(:ai_workflow_node, :mcp_operation) }

        it 'validates valid operation types' do
          %w[tool resource prompt].each do |operation_type|
            node.configuration = node.configuration.merge('operation_type' => operation_type)
            node.valid?
            expect(node.errors[:configuration]).not_to include('operation_type must be one of: tool, resource, prompt')
          end
        end

        it 'rejects invalid operation type' do
          node.configuration = node.configuration.merge('operation_type' => 'invalid_type')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('operation_type must be one of: tool, resource, prompt')
        end

        it 'requires operation_type in configuration' do
          node.configuration = node.configuration.except('operation_type')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('operation_type must be one of: tool, resource, prompt')
        end

        it 'requires mcp_server_id in configuration' do
          node.configuration = node.configuration.merge('mcp_server_id' => nil)
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('must specify mcp_server_id for MCP operation nodes')
        end
      end
    end
  end

  describe 'scopes' do
    let(:workflow) { create(:ai_workflow) }
    let!(:start_node) { create(:ai_workflow_node, :start_node, ai_workflow: workflow) }
    let!(:ai_agent_node) { create(:ai_workflow_node, :ai_agent, ai_workflow: workflow) }
    let!(:end_node) { create(:ai_workflow_node, :end_node, ai_workflow: workflow) }
    let!(:error_handler_node) { create(:ai_workflow_node, :condition, ai_workflow: workflow, is_error_handler: true) }

    describe '.by_type' do
      it 'filters nodes by type' do
        ai_agents = AiWorkflowNode.by_type('ai_agent')
        expect(ai_agents).to include(ai_agent_node)
        expect(ai_agents).not_to include(start_node, end_node)
      end
    end

    describe '.start_nodes' do
      it 'returns only start nodes' do
        start_nodes = AiWorkflowNode.start_nodes
        expect(start_nodes).to include(start_node)
        expect(start_nodes).not_to include(ai_agent_node, end_node)
      end
    end

    describe '.end_nodes' do
      it 'returns only end nodes' do
        end_nodes = AiWorkflowNode.end_nodes
        expect(end_nodes).to include(end_node)
        expect(end_nodes).not_to include(start_node, ai_agent_node)
      end
    end

    describe '.error_handlers' do
      it 'returns nodes marked as error handlers' do
        error_handlers = AiWorkflowNode.error_handlers
        expect(error_handlers).to include(error_handler_node)
        expect(error_handlers).not_to include(start_node, end_node)
      end
    end

    describe '.ordered_by_position' do
      it 'orders nodes by created_at' do
        ordered = workflow.ai_workflow_nodes.ordered_by_position
        expect(ordered.first).to eq(start_node)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default configuration for node types' do
        node = build(:ai_workflow_node, node_type: 'delay', configuration: {})
        node.valid?
        expect(node.configuration).to include('delay_type', 'delay_seconds')
      end
    end

    describe 'after_create' do
      it 'updates workflow metadata' do
        workflow = create(:ai_workflow)
        expect {
          create(:ai_workflow_node, ai_workflow: workflow)
        }.to change { workflow.reload.updated_at }
      end
    end

    describe 'after_destroy' do
      it 'removes associated edges' do
        workflow = create(:ai_workflow)
        node = create(:ai_workflow_node, ai_workflow: workflow)
        other_node = create(:ai_workflow_node, ai_workflow: workflow)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: node.node_id,
               target_node_id: other_node.node_id)

        expect { node.destroy }.to change { AiWorkflowEdge.count }.by(-1)
      end
    end
  end

  describe 'instance methods' do
    describe 'node type check methods' do
      it '#ai_agent_node? returns true for ai_agent nodes' do
        node = build(:ai_workflow_node, :ai_agent)
        expect(node.ai_agent_node?).to be true
        expect(node.condition_node?).to be false
      end

      it '#condition_node? returns true for condition nodes' do
        node = build(:ai_workflow_node, :condition)
        expect(node.condition_node?).to be true
      end

      it '#loop_node? returns true for loop nodes' do
        node = build(:ai_workflow_node, :loop)
        expect(node.loop_node?).to be true
      end

      it '#start_node? returns true for start nodes' do
        node = build(:ai_workflow_node, node_type: 'start')
        expect(node.start_node?).to be true
      end

      it '#end_node? returns true for end nodes' do
        node = build(:ai_workflow_node, node_type: 'end')
        expect(node.end_node?).to be true
      end

      # Consolidated Node Type Helper Methods (Phase 1A)
      it '#kb_article_node? returns true for kb_article nodes' do
        node = build(:ai_workflow_node, :kb_article)
        expect(node.kb_article_node?).to be true
        expect(node.page_node?).to be false
        expect(node.mcp_operation_node?).to be false
      end

      it '#page_node? returns true for page nodes' do
        node = build(:ai_workflow_node, :page)
        expect(node.page_node?).to be true
        expect(node.kb_article_node?).to be false
        expect(node.mcp_operation_node?).to be false
      end

      it '#mcp_operation_node? returns true for mcp_operation nodes' do
        node = build(:ai_workflow_node, :mcp_operation)
        expect(node.mcp_operation_node?).to be true
        expect(node.kb_article_node?).to be false
        expect(node.page_node?).to be false
      end

      it '#kb_article_action returns the action from configuration' do
        node = build(:ai_workflow_node, :kb_article)
        node.configuration = node.configuration.merge('action' => 'search')
        expect(node.kb_article_action).to eq('search')
      end

      it '#page_action returns the action from configuration' do
        node = build(:ai_workflow_node, :page)
        node.configuration = node.configuration.merge('action' => 'publish')
        expect(node.page_action).to eq('publish')
      end

      it '#mcp_operation_type returns the operation_type from configuration' do
        node = build(:ai_workflow_node, :mcp_operation)
        node.configuration = node.configuration.merge('operation_type' => 'resource')
        expect(node.mcp_operation_type).to eq('resource')
      end
    end

    describe '#can_execute?' do
      it 'returns true when configuration is present and valid' do
        node = create(:ai_workflow_node, :api_call)
        expect(node.can_execute?).to be true
      end

      it 'returns false when configuration is invalid' do
        node = create(:ai_workflow_node, :api_call)
        node.update_column(:configuration, {})
        node.reload
        expect(node.can_execute?).to be false
      end
    end

    describe '#next_nodes' do
      let(:node) { create(:ai_workflow_node) }
      let(:next_node1) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }
      let(:next_node2) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }

      before do
        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: node.node_id,
               target_node_id: next_node1.node_id)

        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: node.node_id,
               target_node_id: next_node2.node_id)
      end

      it 'returns all directly connected next nodes' do
        next_nodes = node.next_nodes
        expect(next_nodes).to include(next_node1, next_node2)
      end
    end

    describe '#previous_nodes' do
      let(:node) { create(:ai_workflow_node) }
      let(:prev_node1) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }
      let(:prev_node2) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }

      before do
        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: prev_node1.node_id,
               target_node_id: node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: prev_node2.node_id,
               target_node_id: node.node_id)
      end

      it 'returns all directly connected previous nodes' do
        previous_nodes = node.previous_nodes
        expect(previous_nodes).to include(prev_node1, prev_node2)
      end
    end

    describe '#has_conditions?' do
      let(:node) { create(:ai_workflow_node) }
      let(:other_node) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }

      it 'returns true when node has conditional outgoing edges' do
        create(:ai_workflow_edge, :conditional,
               ai_workflow: node.ai_workflow,
               source_node_id: node.node_id,
               target_node_id: other_node.node_id)

        expect(node.has_conditions?).to be true
      end

      it 'returns false when node has no conditional edges' do
        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: node.node_id,
               target_node_id: other_node.node_id)

        expect(node.has_conditions?).to be false
      end
    end

    describe '#execution_summary' do
      let(:node) { create(:ai_workflow_node) }

      before do
        # Create node executions through separate workflow runs (unique constraint on run_id + node_id)
        3.times do |i|
          run = create(:ai_workflow_run, ai_workflow: node.ai_workflow, account: node.ai_workflow.account)
          status = i < 2 ? 'completed' : 'failed'
          duration = i < 2 ? 1000 + (i * 1000) : nil
          create(:ai_workflow_node_execution, ai_workflow_node: node, ai_workflow_run: run, status: status, duration_ms: duration)
        end
      end

      it 'returns execution statistics' do
        summary = node.execution_summary

        expect(summary[:total_executions]).to eq(3)
        expect(summary[:successful_executions]).to eq(2)
        expect(summary[:failed_executions]).to eq(1)
        expect(summary[:average_duration]).to be_present
      end
    end

    describe '#update_position' do
      let(:node) { create(:ai_workflow_node) }

      it 'updates node position' do
        node.update_position(500, 300)

        expect(node.reload.position['x']).to eq(500)
        expect(node.position['y']).to eq(300)
      end
    end

    describe '#distance_to' do
      let(:node1) { create(:ai_workflow_node, position: { 'x' => 0, 'y' => 0 }) }
      let(:node2) { create(:ai_workflow_node, ai_workflow: node1.ai_workflow, position: { 'x' => 3, 'y' => 4 }) }

      it 'calculates distance between nodes' do
        expect(node1.distance_to(node2)).to eq(5.0)
      end

      it 'returns infinity for non-node objects' do
        expect(node1.distance_to('not a node')).to eq(Float::INFINITY)
      end
    end

    describe '#update_configuration' do
      let(:node) { create(:ai_workflow_node, :api_call) }

      it 'merges new configuration with existing' do
        node.update_configuration({ 'timeout' => 60 })

        expect(node.reload.configuration['timeout']).to eq(60)
        expect(node.configuration['url']).to be_present
      end
    end

    describe '#reset_configuration' do
      let(:node) { create(:ai_workflow_node, :delay) }

      it 'resets configuration to defaults' do
        node.update!(configuration: { 'custom_key' => 'value' })
        node.reset_configuration

        expect(node.reload.configuration).to include('delay_type', 'delay_seconds')
        expect(node.configuration).not_to have_key('custom_key')
      end
    end

    describe '#required_inputs' do
      let(:node) { create(:ai_workflow_node, validation_rules: { 'required_inputs' => [ 'input1', 'input2' ] }) }

      it 'returns required inputs from validation rules' do
        expect(node.required_inputs).to eq([ 'input1', 'input2' ])
      end
    end

    describe '#expected_outputs' do
      let(:node) { create(:ai_workflow_node, validation_rules: { 'expected_outputs' => [ 'output1' ] }) }

      it 'returns expected outputs from validation rules' do
        expect(node.expected_outputs).to eq([ 'output1' ])
      end
    end

    describe '#timeout_duration' do
      it 'returns timeout_seconds if set' do
        node = create(:ai_workflow_node, timeout_seconds: 600)
        expect(node.timeout_duration).to eq(600)
      end

      it 'returns default timeout if not set' do
        node = build(:ai_workflow_node)
        node.timeout_seconds = nil
        expect(node.timeout_duration).to eq(300)
      end
    end

    describe '#max_retries' do
      it 'returns retry_count if set' do
        node = create(:ai_workflow_node, retry_count: 5)
        expect(node.max_retries).to eq(5)
      end

      it 'returns 0 if not set' do
        node = build(:ai_workflow_node)
        node.retry_count = nil
        expect(node.max_retries).to eq(0)
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles unicode characters in node names and configurations' do
      node = create(:ai_workflow_node,
                   name: 'Nœud de traitement avec émojis 🚀',
                   metadata: {
                     'description' => 'Configuration avec caractères spéciaux: àáâãäåæçèéêë',
                     'emoji_test' => '🌟⭐✨🎉🎊'
                   })

      expect(node.reload.name).to include('🚀')
      expect(node.metadata['emoji_test']).to include('🌟')
    end

    it 'handles large configuration objects' do
      large_config = {
        'large_array' => (1..100).to_a,
        'nested_object' => {
          'level1' => {
            'level2' => {
              'data' => Array.new(10) { { id: SecureRandom.uuid } }
            }
          }
        }
      }

      # Merge with valid api_call configuration
      node = create(:ai_workflow_node, :api_call)
      node.update!(configuration: node.configuration.merge(large_config))

      expect(node.reload.configuration['large_array'].size).to eq(100)
    end
  end
end
