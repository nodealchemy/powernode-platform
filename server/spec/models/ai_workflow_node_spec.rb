# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowNode, type: :model do
  describe 'associations' do
    it { should belong_to(:ai_workflow) }
    it { should have_many(:edges_as_source).class_name('AiWorkflowEdge').with_foreign_key('source_node_id').with_primary_key('node_id') }
    it { should have_many(:edges_as_target).class_name('AiWorkflowEdge').with_foreign_key('target_node_id').with_primary_key('node_id') }
    it { should have_many(:executions).class_name('AiWorkflowNodeExecution').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_workflow_node) }

    it { should validate_presence_of(:ai_workflow) }
    it { should validate_presence_of(:node_id) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:node_type) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_inclusion_of(:node_type).in_array(%w[start end ai_agent api_call webhook condition loop transform delay human_approval sub_workflow merge split error_handler]) }

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
      it 'validates configuration is a hash' do
        node = build(:ai_workflow_node, configuration: 'invalid')
        expect(node).not_to be_valid
        expect(node.errors[:configuration]).to include('must be a hash')
      end

      context 'ai_agent node type' do
        let(:node) { build(:ai_workflow_node, :ai_agent) }

        it 'requires provider_id in configuration' do
          node.configuration.delete('provider_id')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('ai_agent nodes must specify provider_id')
        end

        it 'requires model in configuration' do
          node.configuration.delete('model')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('ai_agent nodes must specify model')
        end

        it 'validates temperature range' do
          node.configuration['temperature'] = 2.5
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('temperature must be between 0 and 2')
        end

        it 'validates max_tokens is positive' do
          node.configuration['max_tokens'] = -100
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('max_tokens must be positive')
        end
      end

      context 'api_call node type' do
        let(:node) { build(:ai_workflow_node, :api_call) }

        it 'requires url in configuration' do
          node.configuration.delete('url')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('api_call nodes must specify url')
        end

        it 'requires method in configuration' do
          node.configuration.delete('method')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('api_call nodes must specify method')
        end

        it 'validates HTTP method' do
          node.configuration['method'] = 'INVALID'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('invalid HTTP method')
        end

        it 'validates URL format' do
          node.configuration['url'] = 'not-a-valid-url'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('invalid URL format')
        end

        it 'validates timeout is positive' do
          node.configuration['timeout'] = -5
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('timeout must be positive')
        end
      end

      context 'webhook node type' do
        let(:node) { build(:ai_workflow_node, :webhook) }

        it 'requires url in configuration' do
          node.configuration.delete('url')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('webhook nodes must specify url')
        end

        it 'validates webhook URL format' do
          node.configuration['url'] = 'ftp://invalid-protocol.com'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('webhook URL must use HTTP or HTTPS')
        end

        it 'accepts valid signature secret' do
          node.configuration['signature_secret'] = 'valid_secret_key'
          expect(node).to be_valid
        end
      end

      context 'condition node type' do
        let(:node) { build(:ai_workflow_node, :condition) }

        it 'requires expression in configuration' do
          node.configuration.delete('expression')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('condition nodes must specify expression')
        end

        it 'validates expression syntax' do
          node.configuration['expression'] = 'invalid ( syntax'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('invalid expression syntax')
        end

        it 'accepts valid expressions' do
          valid_expressions = [
            'input.value > 10',
            'output.status == "success"',
            'data.score >= 0.8 && data.confidence > 0.9'
          ]

          valid_expressions.each do |expr|
            node.configuration['expression'] = expr
            expect(node).to be_valid, "Expression '#{expr}' should be valid"
          end
        end
      end

      context 'loop node type' do
        let(:node) { build(:ai_workflow_node, :loop) }

        it 'requires array_path in configuration' do
          node.configuration.delete('array_path')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('loop nodes must specify array_path')
        end

        it 'validates max_iterations is positive' do
          node.configuration['max_iterations'] = -1
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('max_iterations must be positive')
        end

        it 'sets default max_iterations' do
          node.configuration.delete('max_iterations')
          node.valid?
          expect(node.configuration['max_iterations']).to eq(100)
        end
      end

      context 'transform node type' do
        let(:node) { build(:ai_workflow_node, :transform) }

        it 'requires script in configuration' do
          node.configuration.delete('script')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('transform nodes must specify script')
        end

        it 'validates script language' do
          node.configuration['language'] = 'invalid_language'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('unsupported script language')
        end

        it 'accepts valid script languages' do
          %w[javascript python ruby].each do |lang|
            node.configuration['language'] = lang
            expect(node).to be_valid
          end
        end
      end

      context 'delay node type' do
        let(:node) { build(:ai_workflow_node, :delay) }

        it 'requires duration in configuration' do
          node.configuration.delete('duration')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('delay nodes must specify duration')
        end

        it 'validates duration is positive' do
          node.configuration['duration'] = -5
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('duration must be positive')
        end

        it 'validates unit is valid' do
          node.configuration['unit'] = 'invalid_unit'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('invalid time unit')
        end

        it 'accepts valid time units' do
          %w[seconds minutes hours days].each do |unit|
            node.configuration['unit'] = unit
            expect(node).to be_valid
          end
        end
      end

      context 'human_approval node type' do
        let(:node) { build(:ai_workflow_node, :human_approval) }

        it 'validates timeout is reasonable' do
          node.configuration['timeout'] = 86400 * 8 # 8 days
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('timeout cannot exceed 7 days')
        end

        it 'validates required_approvers is positive' do
          node.configuration['required_approvers'] = 0
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('required_approvers must be at least 1')
        end

        it 'validates notification channels' do
          node.configuration['notification_channels'] = ['invalid_channel']
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('invalid notification channel')
        end
      end

      context 'sub_workflow node type' do
        let(:node) { build(:ai_workflow_node, :sub_workflow) }

        it 'requires workflow_id in configuration' do
          node.configuration.delete('workflow_id')
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('sub_workflow nodes must specify workflow_id')
        end

        it 'validates workflow_id exists' do
          node.configuration['workflow_id'] = 'non_existent_id'
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('specified workflow does not exist')
        end

        it 'prevents self-reference' do
          node.configuration['workflow_id'] = node.ai_workflow.id
          expect(node).not_to be_valid
          expect(node.errors[:configuration]).to include('workflow cannot reference itself')
        end
      end
    end

    context 'position validation' do
      it 'validates position is a hash with x and y coordinates' do
        node = build(:ai_workflow_node, position: { x: 100 })
        expect(node).not_to be_valid
        expect(node.errors[:position]).to include('must include x and y coordinates')
      end

      it 'validates coordinates are numeric' do
        node = build(:ai_workflow_node, position: { x: 'invalid', y: 100 })
        expect(node).not_to be_valid
        expect(node.errors[:position]).to include('coordinates must be numeric')
      end

      it 'accepts valid position coordinates' do
        node = build(:ai_workflow_node, position: { x: 100, y: 200 })
        expect(node).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:workflow) { create(:ai_workflow) }
    let!(:start_node) { create(:ai_workflow_node, :start_node, ai_workflow: workflow) }
    let!(:ai_agent_node) { create(:ai_workflow_node, :ai_agent, ai_workflow: workflow) }
    let!(:end_node) { create(:ai_workflow_node, :end_node, ai_workflow: workflow) }
    let!(:condition_node) { create(:ai_workflow_node, :condition, ai_workflow: workflow) }

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

    describe '.executable_nodes' do
      it 'returns nodes that can be executed' do
        executable = AiWorkflowNode.executable_nodes
        expect(executable).to include(ai_agent_node, condition_node)
        expect(executable).not_to include(start_node, end_node)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates node_id if not provided' do
        node = build(:ai_workflow_node, node_id: nil)
        node.valid?
        expect(node.node_id).to be_present
        expect(node.node_id).to match(/^[a-f0-9-]{36}$/) # UUID format
      end

      it 'normalizes node_type' do
        node = build(:ai_workflow_node, node_type: '  AI_AGENT  ')
        node.valid?
        expect(node.node_type).to eq('ai_agent')
      end

      it 'sets default configuration for node types' do
        node = build(:ai_workflow_node, node_type: 'delay', configuration: {})
        node.valid?
        expect(node.configuration).to include('duration', 'unit')
      end
    end

    describe 'after_create' do
      it 'creates audit log entry' do
        expect {
          create(:ai_workflow_node)
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('ai_workflow_node_created')
        expect(audit_log.auditable_type).to eq('AiWorkflowNode')
      end
    end

    describe 'after_destroy' do
      it 'removes associated edges' do
        node = create(:ai_workflow_node)
        other_node = create(:ai_workflow_node, ai_workflow: node.ai_workflow)
        edge = create(:ai_workflow_edge,
                     ai_workflow: node.ai_workflow,
                     source_node_id: node.node_id,
                     target_node_id: other_node.node_id)

        expect { node.destroy }.to change { AiWorkflowEdge.count }.by(-1)
      end
    end
  end

  describe 'instance methods' do
    describe '#can_execute?' do
      it 'returns true for executable node types' do
        executable_types = %w[ai_agent api_call webhook condition loop transform delay human_approval sub_workflow merge split]
        
        executable_types.each do |node_type|
          node = create(:ai_workflow_node, node_type: node_type)
          expect(node.can_execute?).to be true, "#{node_type} should be executable"
        end
      end

      it 'returns false for non-executable node types' do
        non_executable_types = %w[start end]
        
        non_executable_types.each do |node_type|
          node = create(:ai_workflow_node, node_type: node_type)
          expect(node.can_execute?).to be false, "#{node_type} should not be executable"
        end
      end
    end

    describe '#has_connections?' do
      let(:node) { create(:ai_workflow_node) }

      it 'returns false for isolated node' do
        expect(node.has_connections?).to be false
      end

      it 'returns true when node has incoming edges' do
        other_node = create(:ai_workflow_node, ai_workflow: node.ai_workflow)
        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: other_node.node_id,
               target_node_id: node.node_id)

        expect(node.has_connections?).to be true
      end

      it 'returns true when node has outgoing edges' do
        other_node = create(:ai_workflow_node, ai_workflow: node.ai_workflow)
        create(:ai_workflow_edge,
               ai_workflow: node.ai_workflow,
               source_node_id: node.node_id,
               target_node_id: other_node.node_id)

        expect(node.has_connections?).to be true
      end
    end

    describe '#incoming_edges' do
      let(:node) { create(:ai_workflow_node) }
      let(:source_node) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }

      it 'returns edges targeting this node' do
        edge = create(:ai_workflow_edge,
                     ai_workflow: node.ai_workflow,
                     source_node_id: source_node.node_id,
                     target_node_id: node.node_id)

        expect(node.incoming_edges).to include(edge)
      end
    end

    describe '#outgoing_edges' do
      let(:node) { create(:ai_workflow_node) }
      let(:target_node) { create(:ai_workflow_node, ai_workflow: node.ai_workflow) }

      it 'returns edges originating from this node' do
        edge = create(:ai_workflow_edge,
                     ai_workflow: node.ai_workflow,
                     source_node_id: node.node_id,
                     target_node_id: target_node.node_id)

        expect(node.outgoing_edges).to include(edge)
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

    describe '#execution_stats' do
      let(:node) { create(:ai_workflow_node, :with_executions) }

      it 'calculates execution statistics' do
        stats = node.execution_stats
        
        expect(stats).to include(:total_executions)
        expect(stats).to include(:successful_executions)
        expect(stats).to include(:failed_executions)
        expect(stats).to include(:success_rate)
        expect(stats).to include(:avg_execution_time)
      end

      it 'calculates success rate correctly' do
        # Clear existing executions and create specific ones
        node.executions.destroy_all
        create_list(:ai_workflow_node_execution, 3, :completed, ai_workflow_node: node, account: node.ai_workflow.account)
        create_list(:ai_workflow_node_execution, 1, :failed, ai_workflow_node: node, account: node.ai_workflow.account)
        
        stats = node.execution_stats
        expect(stats[:success_rate]).to eq(75.0) # 3 out of 4 successful
      end
    end

    describe '#duplicate' do
      let(:node) { create(:ai_workflow_node, :ai_agent) }

      it 'creates a copy of the node with new node_id' do
        duplicate = node.duplicate

        expect(duplicate.node_id).not_to eq(node.node_id)
        expect(duplicate.name).to eq("#{node.name} (Copy)")
        expect(duplicate.node_type).to eq(node.node_type)
        expect(duplicate.configuration).to eq(node.configuration)
        expect(duplicate.ai_workflow).to eq(node.ai_workflow)
      end

      it 'preserves configuration exactly' do
        node.configuration['custom_setting'] = 'special_value'
        node.save!
        
        duplicate = node.duplicate
        expect(duplicate.configuration['custom_setting']).to eq('special_value')
      end
    end

    describe '#update_configuration' do
      let(:node) { create(:ai_workflow_node, :ai_agent) }

      it 'updates configuration and validates' do
        new_config = node.configuration.merge('temperature' => 0.5)
        result = node.update_configuration(new_config)
        
        expect(result).to be true
        expect(node.configuration['temperature']).to eq(0.5)
      end

      it 'returns false for invalid configuration' do
        invalid_config = node.configuration.merge('temperature' => 3.0)
        result = node.update_configuration(invalid_config)
        
        expect(result).to be false
        expect(node.errors).not_to be_empty
      end

      it 'preserves existing configuration on validation failure' do
        original_temp = node.configuration['temperature']
        invalid_config = node.configuration.merge('temperature' => 3.0)
        
        node.update_configuration(invalid_config)
        expect(node.reload.configuration['temperature']).to eq(original_temp)
      end
    end

    describe '#estimated_execution_time' do
      let(:node) { create(:ai_workflow_node) }

      context 'with execution history' do
        before do
          create(:ai_workflow_node_execution, :completed, ai_workflow_node: node, execution_time_ms: 1000, account: node.ai_workflow.account)
          create(:ai_workflow_node_execution, :completed, ai_workflow_node: node, execution_time_ms: 2000, account: node.ai_workflow.account)
        end

        it 'returns average execution time from history' do
          expect(node.estimated_execution_time).to eq(1500)
        end
      end

      context 'without execution history' do
        it 'returns estimated time based on node type' do
          ai_agent_node = create(:ai_workflow_node, :ai_agent)
          api_call_node = create(:ai_workflow_node, :api_call)
          delay_node = create(:ai_workflow_node, :delay)

          expect(ai_agent_node.estimated_execution_time).to be > api_call_node.estimated_execution_time
          expect(delay_node.estimated_execution_time).to eq(delay_node.configuration['duration'] * 1000)
        end
      end
    end

    describe '#validate_configuration_for_type' do
      it 'validates ai_agent configuration' do
        node = build(:ai_workflow_node, :ai_agent)
        node.configuration.delete('model')
        
        expect(node.send(:validate_configuration_for_type)).to be false
        expect(node.errors[:configuration]).to include('ai_agent nodes must specify model')
      end

      it 'validates api_call configuration' do
        node = build(:ai_workflow_node, :api_call)
        node.configuration['url'] = 'invalid-url'
        
        expect(node.send(:validate_configuration_for_type)).to be false
        expect(node.errors[:configuration]).to include('invalid URL format')
      end

      it 'passes validation for properly configured nodes' do
        node = build(:ai_workflow_node, :ai_agent)
        expect(node.send(:validate_configuration_for_type)).to be true
      end
    end
  end

  describe 'class methods' do
    describe '.node_type_configurations' do
      it 'returns configuration templates for all node types' do
        configs = AiWorkflowNode.node_type_configurations
        
        expect(configs).to include('ai_agent', 'api_call', 'webhook', 'condition')
        expect(configs['ai_agent']).to include('model', 'temperature', 'max_tokens')
        expect(configs['api_call']).to include('url', 'method', 'timeout')
      end
    end

    describe '.validate_node_type' do
      it 'returns true for valid node types' do
        valid_types = %w[ai_agent api_call webhook condition loop transform]
        
        valid_types.each do |type|
          expect(AiWorkflowNode.validate_node_type(type)).to be true
        end
      end

      it 'returns false for invalid node types' do
        invalid_types = %w[invalid_type random_string]
        
        invalid_types.each do |type|
          expect(AiWorkflowNode.validate_node_type(type)).to be false
        end
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles missing position gracefully' do
      node = build(:ai_workflow_node, position: nil)
      node.valid?
      expect(node.position).to be_a(Hash)
      expect(node.position).to include('x', 'y')
    end

    it 'handles malformed JSON in configuration' do
      node = create(:ai_workflow_node)
      # Directly update database to simulate corrupted data
      AiWorkflowNode.where(id: node.id).update_all(configuration: 'invalid json')
      
      expect { node.reload.configuration }.not_to raise_error
      expect(node.configuration).to be_a(Hash)
    end

    it 'validates configuration atomically' do
      node = create(:ai_workflow_node, :ai_agent)
      
      expect {
        node.update!(configuration: { invalid: 'config' })
      }.to raise_error(ActiveRecord::RecordInvalid)
      
      # Original configuration should be preserved
      expect(node.reload.configuration).to include('model', 'temperature')
    end

    it 'handles circular reference detection in sub_workflow nodes' do
      workflow = create(:ai_workflow)
      sub_workflow_node = build(:ai_workflow_node, :sub_workflow, ai_workflow: workflow)
      sub_workflow_node.configuration['workflow_id'] = workflow.id
      
      expect(sub_workflow_node).not_to be_valid
      expect(sub_workflow_node.errors[:configuration]).to include('workflow cannot reference itself')
    end

    it 'handles very long script content in transform nodes' do
      long_script = 'console.log("hello");' * 10000 # Very long script
      node = build(:ai_workflow_node, :transform, configuration: { script: long_script, language: 'javascript' })
      
      expect(node).to be_valid
      expect(node.configuration['script'].length).to be > 100000
    end

    it 'handles unicode characters in node names and configurations' do
      node = create(:ai_workflow_node, 
                   name: 'Nœud de traitement avec émojis 🚀',
                   configuration: { 
                     'description': 'Configuration avec caractères spéciaux: àáâãäåæçèéêë',
                     'emoji_test': '🌟⭐✨🎉🎊'
                   })
      
      expect(node.reload.name).to include('🚀')
      expect(node.configuration['emoji_test']).to include('🌟')
    end
  end

  describe 'performance considerations' do
    it 'efficiently queries nodes with their edges' do
      workflow = create(:ai_workflow)
      nodes = create_list(:ai_workflow_node, 5, ai_workflow: workflow)
      
      # Create edges between nodes
      nodes.each_cons(2) do |source, target|
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: source.node_id,
               target_node_id: target.node_id)
      end
      
      # Test N+1 query prevention
      expect {
        nodes.each { |node| node.next_nodes.to_a }
      }.to execute_queries(count: 6..8) # Should not scale with number of nodes
    end

    it 'handles large configuration objects efficiently' do
      large_config = {
        'large_array' => (1..1000).to_a,
        'nested_object' => {
          'level1' => {
            'level2' => {
              'level3' => Array.new(100) { { id: SecureRandom.uuid, data: Faker::Lorem.paragraph } }
            }
          }
        }
      }
      
      node = create(:ai_workflow_node, configuration: large_config)
      
      # Should handle large configurations without timeout
      expect {
        Timeout.timeout(2.seconds) do
          retrieved_node = AiWorkflowNode.find(node.id)
          expect(retrieved_node.configuration['large_array'].size).to eq(1000)
        end
      }.not_to raise_error
    end
  end
end