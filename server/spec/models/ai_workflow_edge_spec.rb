# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowEdge, type: :model do
  describe 'associations' do
    it { should belong_to(:ai_workflow) }
    it { should belong_to(:source_node).class_name('AiWorkflowNode').with_foreign_key('source_node_id').with_primary_key('node_id') }
    it { should belong_to(:target_node).class_name('AiWorkflowNode').with_foreign_key('target_node_id').with_primary_key('node_id') }
  end

  describe 'validations' do
    subject { build(:ai_workflow_edge) }

    it { should validate_presence_of(:edge_id) }
    it { should validate_presence_of(:source_node_id) }
    it { should validate_presence_of(:target_node_id) }
    it { should validate_presence_of(:edge_type) }
    it { should validate_numericality_of(:priority).is_greater_than_or_equal_to(0) }

    it 'validates inclusion of edge_type' do
      valid_types = %w[default success error conditional retry timeout skip fallback compensation loop]

      valid_types.each do |type|
        edge = build(:ai_workflow_edge, edge_type: type)
        # Clear condition for non-conditional types
        edge.condition = {} unless type == 'conditional'
        edge.is_conditional = false unless type == 'conditional'
        expect(edge).to be_valid, "Expected #{type} to be valid but got errors: #{edge.errors.full_messages.join(', ')}"
      end
    end

    it 'rejects invalid edge_type' do
      edge = build(:ai_workflow_edge, edge_type: 'invalid_type')
      expect(edge).not_to be_valid
      expect(edge.errors[:edge_type]).to include('must be a valid edge type')
    end

    context 'edge_id uniqueness' do
      let!(:existing_edge) { create(:ai_workflow_edge) }

      it 'validates uniqueness of edge_id within workflow scope' do
        workflow = existing_edge.ai_workflow
        node1 = create(:ai_workflow_node, ai_workflow: workflow)
        node2 = create(:ai_workflow_node, ai_workflow: workflow)

        duplicate_edge = build(:ai_workflow_edge,
                              edge_id: existing_edge.edge_id,
                              ai_workflow: workflow,
                              source_node_id: node1.node_id,
                              target_node_id: node2.node_id)

        expect(duplicate_edge).not_to be_valid
        expect(duplicate_edge.errors[:edge_id]).to include('has already been taken')
      end

      it 'allows same edge_id in different workflows' do
        workflow1 = create(:ai_workflow)
        workflow2 = create(:ai_workflow)

        node1_w1 = create(:ai_workflow_node, ai_workflow: workflow1)
        node2_w1 = create(:ai_workflow_node, ai_workflow: workflow1)
        node1_w2 = create(:ai_workflow_node, ai_workflow: workflow2)
        node2_w2 = create(:ai_workflow_node, ai_workflow: workflow2)

        edge1 = create(:ai_workflow_edge,
                      ai_workflow: workflow1,
                      source_node_id: node1_w1.node_id,
                      target_node_id: node2_w1.node_id,
                      edge_id: 'same-edge-id')

        edge2 = build(:ai_workflow_edge,
                     ai_workflow: workflow2,
                     source_node_id: node1_w2.node_id,
                     target_node_id: node2_w2.node_id,
                     edge_id: 'same-edge-id')

        expect(edge2).to be_valid
      end
    end

    context 'self-loop validation' do
      it 'prevents edges from connecting a node to itself' do
        workflow = create(:ai_workflow)
        node = create(:ai_workflow_node, ai_workflow: workflow)

        edge = build(:ai_workflow_edge,
                    ai_workflow: workflow,
                    source_node_id: node.node_id,
                    target_node_id: node.node_id)

        expect(edge).not_to be_valid
        expect(edge.errors[:target_node_id]).to include('cannot be the same as source node (self-loops not allowed)')
      end
    end

    context 'node existence validation' do
      it 'validates source node exists in workflow' do
        workflow = create(:ai_workflow)
        node = create(:ai_workflow_node, ai_workflow: workflow)

        edge = build(:ai_workflow_edge,
                    ai_workflow: workflow,
                    source_node_id: 'non-existent-id',
                    target_node_id: node.node_id)

        expect(edge).not_to be_valid
        expect(edge.errors[:source_node_id]).to include('does not exist in this workflow')
      end

      it 'validates target node exists in workflow' do
        workflow = create(:ai_workflow)
        node = create(:ai_workflow_node, ai_workflow: workflow)

        edge = build(:ai_workflow_edge,
                    ai_workflow: workflow,
                    source_node_id: node.node_id,
                    target_node_id: 'non-existent-id')

        expect(edge).not_to be_valid
        expect(edge.errors[:target_node_id]).to include('does not exist in this workflow')
      end
    end

    context 'conditional configuration validation' do
      it 'validates condition has expression or rules' do
        edge = build(:ai_workflow_edge, :conditional, condition: { 'metadata' => {} })
        edge.is_conditional = true
        expect(edge).not_to be_valid
        expect(edge.errors[:condition]).to include('must contain either expression or rules')
      end

      it 'accepts valid expression conditions' do
        edge = build(:ai_workflow_edge, :conditional,
                    condition: { 'expression' => 'output.status == "success"' })
        expect(edge).to be_valid
      end

      it 'accepts valid rules conditions' do
        edge = build(:ai_workflow_edge, :conditional,
                    condition: {
                      'rules' => [
                        { 'variable' => 'status', 'operator' => '==', 'value' => 'success' }
                      ]
                    })
        expect(edge).to be_valid
      end
    end

    context 'start/end node connection validation' do
      let(:workflow) { create(:ai_workflow) }
      let(:start_node) { create(:ai_workflow_node, :start_node, ai_workflow: workflow) }
      let(:end_node) { create(:ai_workflow_node, :end_node, ai_workflow: workflow) }
      let(:regular_node) { create(:ai_workflow_node, ai_workflow: workflow) }

      it 'prevents outgoing edges from end nodes' do
        edge = build(:ai_workflow_edge,
                    ai_workflow: workflow,
                    source_node_id: end_node.node_id,
                    target_node_id: regular_node.node_id)

        expect(edge).not_to be_valid
        expect(edge.errors[:source_node_id]).to include('end nodes cannot have outgoing edges')
      end

      it 'prevents incoming edges to start nodes' do
        edge = build(:ai_workflow_edge,
                    ai_workflow: workflow,
                    source_node_id: regular_node.node_id,
                    target_node_id: start_node.node_id)

        expect(edge).not_to be_valid
        expect(edge.errors[:target_node_id]).to include('start nodes cannot have incoming edges')
      end
    end
  end

  describe 'scopes' do
    let(:workflow) { create(:ai_workflow) }
    let(:node1) { create(:ai_workflow_node, ai_workflow: workflow) }
    let(:node2) { create(:ai_workflow_node, ai_workflow: workflow) }
    let(:node3) { create(:ai_workflow_node, ai_workflow: workflow) }

    let!(:default_edge) { create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node1.node_id, target_node_id: node2.node_id, edge_type: 'default') }
    let!(:success_edge) { create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node1.node_id, target_node_id: node3.node_id, edge_type: 'success') }
    let!(:error_edge) { create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node2.node_id, target_node_id: node3.node_id, edge_type: 'error') }
    let!(:conditional_edge) { create(:ai_workflow_edge, :conditional, ai_workflow: workflow, source_node_id: node3.node_id, target_node_id: node1.node_id) }

    describe '.by_type' do
      it 'filters edges by type' do
        expect(described_class.by_type('default')).to include(default_edge)
        expect(described_class.by_type('default')).not_to include(success_edge, error_edge)
      end
    end

    describe '.conditional' do
      it 'returns only conditional edges' do
        expect(described_class.conditional).to include(conditional_edge)
        expect(described_class.conditional).not_to include(default_edge)
      end
    end

    describe '.default_edges' do
      it 'returns only default edges' do
        expect(described_class.default_edges).to include(default_edge)
        expect(described_class.default_edges).not_to include(success_edge)
      end
    end

    describe '.success_edges' do
      it 'returns only success edges' do
        expect(described_class.success_edges).to include(success_edge)
        expect(described_class.success_edges).not_to include(default_edge)
      end
    end

    describe '.error_edges' do
      it 'returns only error edges' do
        expect(described_class.error_edges).to include(error_edge)
        expect(described_class.error_edges).not_to include(default_edge)
      end
    end

    describe '.ordered_by_priority' do
      it 'orders edges by priority' do
        default_edge.update!(priority: 10)
        success_edge.update!(priority: 1)

        ordered = described_class.ordered_by_priority
        expect(ordered.first.priority).to be <= ordered.last.priority
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets conditional flag based on condition presence' do
        edge = build(:ai_workflow_edge, condition: { 'expression' => 'test' })
        edge.valid?
        expect(edge.is_conditional).to be true
      end

      it 'does not set conditional flag for empty conditions' do
        edge = build(:ai_workflow_edge, condition: {})
        edge.valid?
        expect(edge.is_conditional).to be false
      end
    end

    describe 'after_create' do
      it 'updates workflow metadata' do
        workflow = create(:ai_workflow)
        node1 = create(:ai_workflow_node, ai_workflow: workflow)
        node2 = create(:ai_workflow_node, ai_workflow: workflow)

        expect {
          create(:ai_workflow_edge, ai_workflow: workflow,
                source_node_id: node1.node_id, target_node_id: node2.node_id)
        }.to change { workflow.reload.updated_at }
      end
    end
  end

  describe 'instance methods' do
    describe 'edge type check methods' do
      it '#default_edge? returns true for default edges' do
        edge = build(:ai_workflow_edge, edge_type: 'default')
        expect(edge.default_edge?).to be true
        expect(edge.error_edge?).to be false
      end

      it '#success_edge? returns true for success edges' do
        edge = build(:ai_workflow_edge, edge_type: 'success')
        expect(edge.success_edge?).to be true
      end

      it '#error_edge? returns true for error edges' do
        edge = build(:ai_workflow_edge, edge_type: 'error')
        expect(edge.error_edge?).to be true
      end

      it '#conditional_edge? returns true for conditional edges' do
        edge = build(:ai_workflow_edge, edge_type: 'conditional')
        expect(edge.conditional_edge?).to be true
      end

      it '#loop_edge? returns true for loop edges' do
        edge = build(:ai_workflow_edge, edge_type: 'loop')
        expect(edge.loop_edge?).to be true
      end

      it '#retry_edge? returns true for retry edges' do
        edge = build(:ai_workflow_edge, edge_type: 'retry')
        expect(edge.retry_edge?).to be true
      end

      it '#timeout_edge? returns true for timeout edges' do
        edge = build(:ai_workflow_edge, edge_type: 'timeout')
        expect(edge.timeout_edge?).to be true
      end

      it '#fallback_edge? returns true for fallback edges' do
        edge = build(:ai_workflow_edge, edge_type: 'fallback')
        expect(edge.fallback_edge?).to be true
      end

      it '#compensation_edge? returns true for compensation edges' do
        edge = build(:ai_workflow_edge, edge_type: 'compensation')
        expect(edge.compensation_edge?).to be true
      end
    end

    describe '#evaluate_condition' do
      let(:edge) { create(:ai_workflow_edge) }

      it 'returns true when no condition is set' do
        edge.update!(condition: {}, is_conditional: false)
        expect(edge.evaluate_condition({})).to be true
      end

      it 'evaluates expression conditions' do
        edge.update!(condition: { 'expression' => 'true' }, is_conditional: true)
        expect(edge.evaluate_condition({})).to be true
      end

      it 'evaluates rule conditions with AND logic' do
        edge.update!(condition: {
          'rules' => [
            { 'variable' => 'status', 'operator' => '==', 'value' => 'success' },
            { 'variable' => 'count', 'operator' => '>', 'value' => 5 }
          ],
          'logic' => 'AND'
        }, is_conditional: true)

        expect(edge.evaluate_condition({ 'status' => 'success', 'count' => 10 })).to be true
        expect(edge.evaluate_condition({ 'status' => 'success', 'count' => 3 })).to be false
      end

      it 'evaluates rule conditions with OR logic' do
        edge.update!(condition: {
          'rules' => [
            { 'variable' => 'status', 'operator' => '==', 'value' => 'success' },
            { 'variable' => 'override', 'operator' => '==', 'value' => true }
          ],
          'logic' => 'OR'
        }, is_conditional: true)

        expect(edge.evaluate_condition({ 'status' => 'failed', 'override' => true })).to be true
        expect(edge.evaluate_condition({ 'status' => 'failed', 'override' => false })).to be false
      end
    end

    describe '#condition_summary' do
      it 'returns "Always" for non-conditional edges' do
        edge = build(:ai_workflow_edge, condition: {}, is_conditional: false)
        expect(edge.condition_summary).to eq('Always')
      end

      it 'returns expression for expression conditions' do
        edge = build(:ai_workflow_edge, condition: { 'expression' => 'status == "success"' }, is_conditional: true)
        expect(edge.condition_summary).to eq('status == "success"')
      end

      it 'summarizes rule conditions' do
        edge = build(:ai_workflow_edge, condition: {
          'rules' => [
            { 'variable' => 'status', 'operator' => '==', 'value' => 'success' }
          ],
          'logic' => 'AND'
        }, is_conditional: true)

        expect(edge.condition_summary).to include('status')
      end
    end

    describe '#has_condition?' do
      it 'returns true when is_conditional is set' do
        edge = build(:ai_workflow_edge, is_conditional: true, condition: { 'expression' => 'test' })
        expect(edge.has_condition?).to be true
      end

      it 'returns true when condition is present' do
        edge = build(:ai_workflow_edge, condition: { 'expression' => 'test' })
        expect(edge.has_condition?).to be true
      end

      it 'returns false when no condition' do
        edge = build(:ai_workflow_edge, condition: {}, is_conditional: false)
        expect(edge.has_condition?).to be false
      end
    end

    describe '#condition_variables' do
      it 'extracts variables from expression' do
        edge = build(:ai_workflow_edge, condition: {
          'expression' => '${status} == "success" && $count > 5'
        })

        variables = edge.condition_variables
        expect(variables).to include('status', 'count')
      end

      it 'extracts variables from rules' do
        edge = build(:ai_workflow_edge, condition: {
          'rules' => [
            { 'variable' => 'status', 'operator' => '==', 'value' => 'success' },
            { 'variable' => 'count', 'operator' => '>', 'value' => 5 }
          ]
        })

        variables = edge.condition_variables
        expect(variables).to include('status', 'count')
      end

      it 'returns empty array when no condition' do
        edge = build(:ai_workflow_edge, condition: {})
        expect(edge.condition_variables).to eq([])
      end
    end

    describe '#is_error_fallback?' do
      it 'returns true for error edges' do
        edge = build(:ai_workflow_edge, edge_type: 'error')
        expect(edge.is_error_fallback?).to be true
      end

      it 'returns true when configuration specifies error fallback' do
        edge = build(:ai_workflow_edge, configuration: { 'is_error_fallback' => true })
        expect(edge.is_error_fallback?).to be true
      end
    end

    describe '#should_execute_on_success?' do
      it 'returns true for default edges' do
        edge = build(:ai_workflow_edge, edge_type: 'default')
        expect(edge.should_execute_on_success?).to be true
      end

      it 'returns true for success edges' do
        edge = build(:ai_workflow_edge, edge_type: 'success')
        expect(edge.should_execute_on_success?).to be true
      end

      it 'returns false for error edges' do
        edge = build(:ai_workflow_edge, edge_type: 'error')
        expect(edge.should_execute_on_success?).to be false
      end
    end

    describe '#should_execute_on_error?' do
      it 'returns true for error edges' do
        edge = build(:ai_workflow_edge, edge_type: 'error')
        expect(edge.should_execute_on_error?).to be true
      end

      it 'returns true when configuration specifies execute_on_error' do
        edge = build(:ai_workflow_edge, configuration: { 'execute_on_error' => true })
        expect(edge.should_execute_on_error?).to be true
      end

      it 'returns false for default edges' do
        edge = build(:ai_workflow_edge, edge_type: 'default')
        expect(edge.should_execute_on_error?).to be false
      end
    end

    describe '#creates_cycle?' do
      let(:workflow) { create(:ai_workflow) }
      let(:node1) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:node2) { create(:ai_workflow_node, ai_workflow: workflow) }
      let(:node3) { create(:ai_workflow_node, ai_workflow: workflow) }

      before do
        create(:ai_workflow_edge, ai_workflow: workflow,
              source_node_id: node1.node_id, target_node_id: node2.node_id)
        create(:ai_workflow_edge, ai_workflow: workflow,
              source_node_id: node2.node_id, target_node_id: node3.node_id)
      end

      it 'detects cycles' do
        # This edge would create: node1 -> node2 -> node3 -> node1 (cycle)
        edge = build(:ai_workflow_edge, ai_workflow: workflow,
                    source_node_id: node3.node_id, target_node_id: node1.node_id)

        expect(edge.creates_cycle?).to be true
      end

      it 'returns false when no cycle' do
        node4 = create(:ai_workflow_node, ai_workflow: workflow)
        edge = build(:ai_workflow_edge, ai_workflow: workflow,
                    source_node_id: node3.node_id, target_node_id: node4.node_id)

        expect(edge.creates_cycle?).to be false
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles unicode in configuration' do
      edge = create(:ai_workflow_edge,
                   configuration: {
                     'label' => 'Connexion spéciale 🔗',
                     'description' => '日本語テスト'
                   })

      expect(edge.reload.configuration['label']).to include('🔗')
      expect(edge.configuration['description']).to include('日本語')
    end
  end
end
