# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowEdge, type: :model do
  subject(:edge) { build(:ai_workflow_edge) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
    it { is_expected.to belong_to(:source_node).class_name('AiWorkflowNode') }
    it { is_expected.to belong_to(:target_node).class_name('AiWorkflowNode') }
  end

  describe 'validations' do
    context 'basic validations' do
      it { is_expected.to validate_presence_of(:ai_workflow) }
      it { is_expected.to validate_presence_of(:source_node) }
      it { is_expected.to validate_presence_of(:target_node) }
      it { is_expected.to validate_presence_of(:edge_type) }
      it { is_expected.to validate_inclusion_of(:edge_type).in_array(%w[default conditional loop error parallel merge]) }
    end

    context 'workflow consistency' do
      let(:workflow1) { create(:ai_workflow) }
      let(:workflow2) { create(:ai_workflow) }
      let(:source_node) { create(:ai_workflow_node, ai_workflow: workflow1) }
      let(:target_node) { create(:ai_workflow_node, ai_workflow: workflow2) }

      it 'validates that source and target nodes belong to the same workflow' do
        edge = build(:ai_workflow_edge, 
                    ai_workflow: workflow1,
                    source_node: source_node,
                    target_node: target_node)
        
        expect(edge).not_to be_valid
        expect(edge.errors[:target_node]).to include('must belong to the same workflow as source node')
      end

      it 'validates that edge workflow matches node workflows' do
        target_node_same = create(:ai_workflow_node, ai_workflow: workflow1)
        edge = build(:ai_workflow_edge,
                    ai_workflow: workflow2,
                    source_node: source_node,
                    target_node: target_node_same)
        
        expect(edge).not_to be_valid
        expect(edge.errors[:ai_workflow]).to include('must match the workflow of the connected nodes')
      end
    end

    context 'self-reference validation' do
      let(:node) { create(:ai_workflow_node) }
      
      it 'prevents nodes from connecting to themselves' do
        edge = build(:ai_workflow_edge,
                    source_node: node,
                    target_node: node,
                    ai_workflow: node.ai_workflow)
        
        expect(edge).not_to be_valid
        expect(edge.errors[:target_node]).to include('cannot be the same as source node')
      end
    end

    context 'conditional edge validations' do
      it 'requires condition when edge_type is conditional' do
        edge = build(:ai_workflow_edge, :conditional, condition: nil)
        expect(edge).not_to be_valid
        expect(edge.errors[:condition]).to include("can't be blank for conditional edges")
      end

      it 'validates condition format for conditional edges' do
        edge = build(:ai_workflow_edge, :conditional, condition: 'invalid condition')
        expect(edge).not_to be_valid
        expect(edge.errors[:condition]).to include('must be a valid conditional expression')
      end

      it 'accepts valid conditional expressions' do
        valid_conditions = [
          'output.status == "success"',
          'result.score > 0.8',
          'data.type === "premium"',
          'variables.count >= 10',
          'response.error == null'
        ]

        valid_conditions.each do |condition|
          edge = build(:ai_workflow_edge, :conditional, condition: condition)
          expect(edge).to be_valid, "Expected '#{condition}' to be valid"
        end
      end
    end

    context 'loop edge validations' do
      it 'requires loop_config when edge_type is loop' do
        edge = build(:ai_workflow_edge, :loop, loop_config: nil)
        expect(edge).not_to be_valid
        expect(edge.errors[:loop_config]).to include("can't be blank for loop edges")
      end

      it 'validates loop_config structure' do
        edge = build(:ai_workflow_edge, :loop, 
                    loop_config: { invalid: 'config' })
        expect(edge).not_to be_valid
        expect(edge.errors[:loop_config]).to include('must contain max_iterations')
      end

      it 'validates max_iterations is positive' do
        edge = build(:ai_workflow_edge, :loop,
                    loop_config: { max_iterations: -1 })
        expect(edge).not_to be_valid
        expect(edge.errors[:loop_config]).to include('max_iterations must be positive')
      end

      it 'accepts valid loop configuration' do
        edge = build(:ai_workflow_edge, :loop,
                    loop_config: {
                      max_iterations: 10,
                      break_condition: 'output.complete == true',
                      iteration_variable: 'current_item'
                    })
        expect(edge).to be_valid
      end
    end

    context 'parallel edge validations' do
      it 'validates parallel_config structure when provided' do
        edge = build(:ai_workflow_edge, :parallel,
                    parallel_config: { invalid: 'structure' })
        expect(edge).not_to be_valid
        expect(edge.errors[:parallel_config]).to include('must contain valid parallel execution settings')
      end

      it 'accepts valid parallel configuration' do
        edge = build(:ai_workflow_edge, :parallel,
                    parallel_config: {
                      max_concurrent: 5,
                      wait_for_completion: true,
                      merge_strategy: 'combine_outputs'
                    })
        expect(edge).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:default_edge) { create(:ai_workflow_edge, edge_type: 'default') }
    let!(:conditional_edge) { create(:ai_workflow_edge, :conditional) }
    let!(:loop_edge) { create(:ai_workflow_edge, :loop) }
    let!(:error_edge) { create(:ai_workflow_edge, :error) }
    let!(:active_edge) { create(:ai_workflow_edge, is_active: true) }
    let!(:inactive_edge) { create(:ai_workflow_edge, is_active: false) }

    describe '.by_type' do
      it 'filters edges by type' do
        expect(described_class.by_type('conditional')).to include(conditional_edge)
        expect(described_class.by_type('conditional')).not_to include(default_edge)
      end
    end

    describe '.active' do
      it 'returns only active edges' do
        expect(described_class.active).to include(active_edge)
        expect(described_class.active).not_to include(inactive_edge)
      end
    end

    describe '.conditional' do
      it 'returns only conditional edges' do
        expect(described_class.conditional).to include(conditional_edge)
        expect(described_class.conditional).not_to include(default_edge)
      end
    end

    describe '.loops' do
      it 'returns only loop edges' do
        expect(described_class.loops).to include(loop_edge)
        expect(described_class.loops).not_to include(default_edge)
      end
    end

    describe '.error_handling' do
      it 'returns only error edges' do
        expect(described_class.error_handling).to include(error_edge)
        expect(described_class.error_handling).not_to include(default_edge)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'normalizes edge_type' do
        edge = build(:ai_workflow_edge, edge_type: '  CONDITIONAL  ')
        edge.valid?
        expect(edge.edge_type).to eq('conditional')
      end

      it 'sets default priority if not provided' do
        edge = build(:ai_workflow_edge, priority: nil)
        edge.valid?
        expect(edge.priority).to eq(1)
      end
    end

    describe 'after_create' do
      it 'invalidates workflow cache' do
        workflow = create(:ai_workflow)
        source_node = create(:ai_workflow_node, ai_workflow: workflow)
        target_node = create(:ai_workflow_node, ai_workflow: workflow)
        
        expect(workflow).to receive(:invalidate_structure_cache)
        
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node: source_node,
               target_node: target_node)
      end
    end
  end

  describe 'instance methods' do
    describe '#evaluable?' do
      it 'returns true for conditional edges with valid conditions' do
        edge = create(:ai_workflow_edge, :conditional)
        expect(edge.evaluable?).to be true
      end

      it 'returns false for non-conditional edges' do
        edge = create(:ai_workflow_edge, edge_type: 'default')
        expect(edge.evaluable?).to be false
      end

      it 'returns false for conditional edges without conditions' do
        edge = create(:ai_workflow_edge, edge_type: 'conditional', condition: nil)
        expect(edge.evaluable?).to be false
      end
    end

    describe '#evaluate_condition' do
      let(:edge) { create(:ai_workflow_edge, :conditional, 
                         condition: 'output.status == "success"') }

      it 'evaluates true when condition is met' do
        context = { 'output' => { 'status' => 'success' } }
        expect(edge.evaluate_condition(context)).to be true
      end

      it 'evaluates false when condition is not met' do
        context = { 'output' => { 'status' => 'failed' } }
        expect(edge.evaluate_condition(context)).to be false
      end

      it 'handles missing context gracefully' do
        expect(edge.evaluate_condition({})).to be false
      end

      it 'handles complex nested conditions' do
        edge = create(:ai_workflow_edge, :conditional,
                     condition: 'data.user.score > 0.8 && data.user.verified == true')
        
        context = {
          'data' => {
            'user' => {
              'score' => 0.9,
              'verified' => true
            }
          }
        }
        
        expect(edge.evaluate_condition(context)).to be true
      end

      it 'returns false for non-conditional edges' do
        edge = create(:ai_workflow_edge, edge_type: 'default')
        expect(edge.evaluate_condition({ 'test' => 'data' })).to be false
      end
    end

    describe '#should_execute?' do
      let(:context) { { 'status' => 'success' } }

      it 'returns true for active default edges' do
        edge = create(:ai_workflow_edge, edge_type: 'default', is_active: true)
        expect(edge.should_execute?(context)).to be true
      end

      it 'returns false for inactive edges' do
        edge = create(:ai_workflow_edge, is_active: false)
        expect(edge.should_execute?(context)).to be false
      end

      it 'evaluates condition for conditional edges' do
        edge = create(:ai_workflow_edge, :conditional,
                     condition: 'status == "success"')
        
        expect(edge.should_execute?(context)).to be true
        expect(edge.should_execute?({ 'status' => 'failed' })).to be false
      end
    end

    describe '#execution_weight' do
      it 'returns priority for default edges' do
        edge = create(:ai_workflow_edge, priority: 5)
        expect(edge.execution_weight).to eq(5)
      end

      it 'factors in condition complexity for conditional edges' do
        simple_edge = create(:ai_workflow_edge, :conditional,
                           condition: 'status == "success"',
                           priority: 1)
        
        complex_edge = create(:ai_workflow_edge, :conditional,
                            condition: 'data.user.score > 0.8 && data.user.verified == true && data.premium == true',
                            priority: 1)
        
        expect(complex_edge.execution_weight).to be > simple_edge.execution_weight
      end
    end

    describe '#can_loop?' do
      it 'returns true for loop edges with valid config' do
        edge = create(:ai_workflow_edge, :loop)
        expect(edge.can_loop?).to be true
      end

      it 'returns false for non-loop edges' do
        edge = create(:ai_workflow_edge, edge_type: 'default')
        expect(edge.can_loop?).to be false
      end

      it 'returns false for loop edges without config' do
        edge = create(:ai_workflow_edge, edge_type: 'loop', loop_config: nil)
        expect(edge.can_loop?).to be false
      end
    end

    describe '#max_iterations' do
      it 'returns max_iterations from loop_config' do
        edge = create(:ai_workflow_edge, :loop,
                     loop_config: { max_iterations: 15 })
        expect(edge.max_iterations).to eq(15)
      end

      it 'returns 0 for non-loop edges' do
        edge = create(:ai_workflow_edge, edge_type: 'default')
        expect(edge.max_iterations).to eq(0)
      end
    end

    describe '#supports_parallel_execution?' do
      it 'returns true for parallel edges' do
        edge = create(:ai_workflow_edge, :parallel)
        expect(edge.supports_parallel_execution?).to be true
      end

      it 'returns true for merge edges' do
        edge = create(:ai_workflow_edge, :merge)
        expect(edge.supports_parallel_execution?).to be true
      end

      it 'returns false for other edge types' do
        edge = create(:ai_workflow_edge, edge_type: 'default')
        expect(edge.supports_parallel_execution?).to be false
      end
    end

    describe '#to_graph_representation' do
      it 'returns hash representation for graph visualization' do
        edge = create(:ai_workflow_edge, :conditional)
        
        representation = edge.to_graph_representation
        
        expect(representation).to include(
          :id,
          :source_node_id,
          :target_node_id,
          :edge_type,
          :condition,
          :priority,
          :is_active
        )
        expect(representation[:id]).to eq(edge.id)
        expect(representation[:source_node_id]).to eq(edge.source_node_id)
        expect(representation[:target_node_id]).to eq(edge.target_node_id)
      end

      it 'includes loop configuration for loop edges' do
        edge = create(:ai_workflow_edge, :loop)
        representation = edge.to_graph_representation
        
        expect(representation).to include(:loop_config)
        expect(representation[:loop_config]).to eq(edge.loop_config)
      end

      it 'includes parallel configuration for parallel edges' do
        edge = create(:ai_workflow_edge, :parallel)
        representation = edge.to_graph_representation
        
        expect(representation).to include(:parallel_config)
        expect(representation[:parallel_config]).to eq(edge.parallel_config)
      end
    end
  end

  describe 'class methods' do
    describe '.validate_condition_syntax' do
      it 'validates JavaScript-like condition syntax' do
        valid_conditions = [
          'output.status == "success"',
          'result.score > 0.8',
          'data.count >= 10',
          'user.verified === true',
          'response.error == null'
        ]

        valid_conditions.each do |condition|
          expect(described_class.validate_condition_syntax(condition)).to be true
        end
      end

      it 'rejects invalid syntax' do
        invalid_conditions = [
          'output.status =',
          'result.score > ',
          'invalid syntax here',
          'SELECT * FROM users',
          'function() { return true; }'
        ]

        invalid_conditions.each do |condition|
          expect(described_class.validate_condition_syntax(condition)).to be false
        end
      end
    end

    describe '.validate_loop_config' do
      it 'validates required loop configuration fields' do
        valid_config = {
          max_iterations: 10,
          break_condition: 'output.complete == true'
        }
        
        expect(described_class.validate_loop_config(valid_config)).to be true
      end

      it 'rejects config without max_iterations' do
        invalid_config = { break_condition: 'output.complete == true' }
        expect(described_class.validate_loop_config(invalid_config)).to be false
      end

      it 'rejects config with invalid max_iterations' do
        invalid_config = { max_iterations: -1 }
        expect(described_class.validate_loop_config(invalid_config)).to be false
      end
    end

    describe '.validate_parallel_config' do
      it 'validates parallel execution configuration' do
        valid_config = {
          max_concurrent: 5,
          wait_for_completion: true,
          merge_strategy: 'combine_outputs'
        }
        
        expect(described_class.validate_parallel_config(valid_config)).to be true
      end

      it 'accepts minimal valid configuration' do
        minimal_config = { max_concurrent: 1 }
        expect(described_class.validate_parallel_config(minimal_config)).to be true
      end

      it 'rejects invalid merge strategies' do
        invalid_config = {
          max_concurrent: 5,
          merge_strategy: 'invalid_strategy'
        }
        
        expect(described_class.validate_parallel_config(invalid_config)).to be false
      end
    end

    describe '.execution_order' do
      let(:workflow) { create(:ai_workflow) }
      let(:source) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:target1) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:target2) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:target3) { create(:ai_workflow_node, ai_workflow: workflow) }

      let!(:edge1) { create(:ai_workflow_edge, ai_workflow: workflow, source_node: source, target_node: target1, priority: 3) }
      let!(:edge2) { create(:ai_workflow_edge, ai_workflow: workflow, source_node: source, target_node: target2, priority: 1) }
      let!(:edge3) { create(:ai_workflow_edge, ai_workflow: workflow, source_node: source, target_node: target3, priority: 2) }

      it 'returns edges in priority order' do
        ordered_edges = described_class.execution_order
        expect(ordered_edges.first).to eq(edge2)  # priority 1
        expect(ordered_edges.second).to eq(edge3) # priority 2
        expect(ordered_edges.third).to eq(edge1)  # priority 3
      end
    end

    describe '.find_circular_references' do
      let(:workflow) { create(:ai_workflow) }
      let(:node1) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:node2) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:node3) { create(:ai_workflow_node, ai_workflow: workflow) }

      it 'detects circular references in workflow' do
        # Create a circle: node1 -> node2 -> node3 -> node1
        create(:ai_workflow_edge, ai_workflow: workflow, source_node: node1, target_node: node2)
        create(:ai_workflow_edge, ai_workflow: workflow, source_node: node2, target_node: node3)
        create(:ai_workflow_edge, ai_workflow: workflow, source_node: node3, target_node: node1)

        circular_refs = described_class.find_circular_references(workflow.id)
        expect(circular_refs).not_to be_empty
        expect(circular_refs.flatten).to include(node1.id, node2.id, node3.id)
      end

      it 'returns empty array for acyclic workflows' do
        # Create a linear flow: node1 -> node2 -> node3
        create(:ai_workflow_edge, ai_workflow: workflow, source_node: node1, target_node: node2)
        create(:ai_workflow_edge, ai_workflow: workflow, source_node: node2, target_node: node3)

        circular_refs = described_class.find_circular_references(workflow.id)
        expect(circular_refs).to be_empty
      end
    end
  end

  describe 'edge cases and performance' do
    describe 'large condition strings' do
      it 'handles very long condition expressions' do
        long_condition = Array.new(100) { |i| "data.field#{i} == 'value#{i}'" }.join(' && ')
        edge = build(:ai_workflow_edge, :conditional, condition: long_condition)
        
        expect { edge.save! }.not_to raise_error
        expect(edge.condition.length).to be > 1000
      end
    end

    describe 'complex nested context evaluation' do
      it 'evaluates deeply nested object conditions' do
        edge = create(:ai_workflow_edge, :conditional,
                     condition: 'data.level1.level2.level3.level4.value == "deep"')
        
        context = {
          'data' => {
            'level1' => {
              'level2' => {
                'level3' => {
                  'level4' => {
                    'value' => 'deep'
                  }
                }
              }
            }
          }
        }
        
        expect(edge.evaluate_condition(context)).to be true
      end

      it 'handles missing nested properties gracefully' do
        edge = create(:ai_workflow_edge, :conditional,
                     condition: 'data.missing.property == "value"')
        
        context = { 'data' => {} }
        expect(edge.evaluate_condition(context)).to be false
      end
    end

    describe 'unicode and special character handling' do
      it 'handles unicode characters in conditions' do
        edge = create(:ai_workflow_edge, :conditional,
                     condition: 'output.message == "完成"')
        
        context = { 'output' => { 'message' => '完成' } }
        expect(edge.evaluate_condition(context)).to be true
      end

      it 'handles special characters in node metadata' do
        edge = build(:ai_workflow_edge,
                    metadata: {
                      'description' => 'Edge with émojis 🚀 and spëcial chars',
                      'tags' => ['tëst', 'spëcial']
                    })
        
        expect(edge).to be_valid
        expect(edge.metadata['description']).to include('🚀')
      end
    end

    describe 'concurrent edge execution scenarios' do
      let(:workflow) { create(:ai_workflow) }
      let(:source) { create(:ai_workflow_node, ai_workflow: workflow) }

      it 'handles multiple parallel edges from same source' do
        targets = create_list(:ai_workflow_node, 5, ai_workflow: workflow)
        
        edges = targets.map do |target|
          create(:ai_workflow_edge, :parallel,
                 ai_workflow: workflow,
                 source_node: source,
                 target_node: target)
        end
        
        expect(edges.all?(&:supports_parallel_execution?)).to be true
        expect(edges.map(&:source_node).uniq.size).to eq(1)
      end
    end

    describe 'performance with large numbers of edges' do
      it 'efficiently queries edges for large workflows' do
        workflow = create(:ai_workflow)
        nodes = create_list(:ai_workflow_node, 50, ai_workflow: workflow)
        
        # Create a complex network of edges
        nodes.each_with_index do |source, i|
          targets = nodes[(i + 1)..(i + 5)] || []
          targets.each do |target|
            create(:ai_workflow_edge,
                   ai_workflow: workflow,
                   source_node: source,
                   target_node: target)
          end
        end
        
        expect {
          described_class.joins(:source_node, :target_node)
                        .where(ai_workflow: workflow)
                        .active
                        .execution_order
                        .limit(100)
                        .to_a
        }.not_to exceed_query_limit(5)
      end
    end
  end
end