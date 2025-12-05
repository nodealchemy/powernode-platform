# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::WorkflowCheckpointManager, type: :service do
  include AiOrchestrationHelpers

  let(:env) { setup_ai_orchestration_environment }
  let(:account) { env[:account] }
  let(:user) { env[:user] }
  let(:workflow) do
    create(:ai_workflow, :with_simple_chain, account: account, creator: user)
  end
  let(:workflow_run) do
    create(:ai_workflow_run,
      ai_workflow: workflow,
      account: account,
      triggered_by_user: user,
      status: 'running',
      runtime_context: { 'variables' => { 'key' => 'value' } }
    )
  end
  let(:manager) { described_class.new(workflow_run: workflow_run, account: account, user: user) }

  before do
    # Stub logging to avoid expectations on unstubbed logger
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    # Stub ActionCable broadcasting
    stub_action_cable_broadcasting

    # Create some completed node executions for testing
    workflow.ai_workflow_nodes.first(2).each do |node|
      create(:ai_workflow_node_execution, :completed,
        ai_workflow_run: workflow_run,
        ai_workflow_node: node,
        node_id: node.node_id
      )
    end
  end

  describe '#initialize' do
    it 'initializes with workflow run and context' do
      expect(manager.workflow_run).to eq(workflow_run)
      expect(manager.account).to eq(account)
      expect(manager.user).to eq(user)
      expect(manager.logger).to be_present
    end
  end

  describe '#create_checkpoint' do
    let(:node_id) { 'test-node-123' }
    let(:checkpoint_data) { { step: 1, progress: 50 } }

    it 'creates a checkpoint with unique ID' do
      checkpoint_id = manager.create_checkpoint(node_id, checkpoint_data)

      expect(checkpoint_id).to be_present
      expect(checkpoint_id).to be_a(String)
      expect(checkpoint_id.length).to eq(36) # UUID format
    end

    it 'captures current workflow state' do
      allow(manager).to receive(:capture_workflow_state).and_call_original

      manager.create_checkpoint(node_id, checkpoint_data)

      expect(manager).to have_received(:capture_workflow_state)
    end

    it 'stores checkpoint in cache' do
      checkpoint_id = manager.create_checkpoint(node_id, checkpoint_data)

      stored = manager.load_checkpoint(checkpoint_id)
      expect(stored).to be_present
      expect(stored['id']).to eq(checkpoint_id)
      expect(stored['node_id']).to eq(node_id)
      expect(stored['data']).to include(step: 1, progress: 50)
    end

    it 'sets appropriate TTL for checkpoint' do
      expect(Rails.cache).to receive(:write).with(
        anything,
        anything,
        hash_including(expires_in: 24.hours)
      )

      manager.create_checkpoint(node_id, checkpoint_data)
    end

    it 'updates workflow run metadata with checkpoint reference' do
      checkpoint_id = manager.create_checkpoint(node_id, checkpoint_data)

      workflow_run.reload
      expect(workflow_run.metadata['last_checkpoint_id']).to eq(checkpoint_id)
      expect(workflow_run.metadata['last_checkpoint_at']).to be_present
    end

    it 'includes completed nodes in checkpoint' do
      checkpoint_id = manager.create_checkpoint(node_id, checkpoint_data)

      stored = manager.load_checkpoint(checkpoint_id)
      completed_node_id = workflow.ai_workflow_nodes.first.node_id
      expect(stored['completed_nodes']).to include(completed_node_id)
    end

    it 'includes runtime variables in checkpoint' do
      checkpoint_id = manager.create_checkpoint(node_id, checkpoint_data)
      
      stored = manager.load_checkpoint(checkpoint_id)
      expect(stored['variables']).to eq({ 'key' => 'value' })
    end
  end

  describe '#restore_from_checkpoint' do
    let(:checkpoint_id) { manager.create_checkpoint('node-2', { step: 2 }) }

    context 'when checkpoint exists' do
      it 'restores workflow state from checkpoint' do
        result = manager.restore_from_checkpoint(checkpoint_id)

        expect(result).to be true
      end

      it 'updates workflow run with restored state' do
        manager.restore_from_checkpoint(checkpoint_id)

        workflow_run.reload
        expect(workflow_run.runtime_context['restored_from_checkpoint']).to eq(checkpoint_id)
        expect(workflow_run.runtime_context['restored_at']).to be_present
        expect(workflow_run.metadata['restored_from_checkpoint']).to eq(checkpoint_id)
      end

      it 'restores variables from checkpoint' do
        # Create checkpoint with specific variables
        workflow_run.update!(runtime_context: { 'variables' => { 'original' => 'data' } })
        checkpoint_id = manager.create_checkpoint('node-3', {})
        
        # Change variables
        workflow_run.update!(runtime_context: { 'variables' => { 'changed' => 'value' } })
        
        # Restore
        manager.restore_from_checkpoint(checkpoint_id)

        workflow_run.reload
        expect(workflow_run.runtime_context['variables']).to eq({ 'original' => 'data' })
      end

      it 'marks completed nodes as already executed' do
        allow(manager).to receive(:mark_nodes_as_completed).and_call_original

        manager.restore_from_checkpoint(checkpoint_id)

        expect(manager).to have_received(:mark_nodes_as_completed)
      end
    end

    context 'when checkpoint does not exist' do
      it 'returns false' do
        result = manager.restore_from_checkpoint('non-existent-id')

        expect(result).to be false
      end

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn).with(/No checkpoint found/)

        manager.restore_from_checkpoint('non-existent-id')
      end
    end

    context 'when no checkpoint ID provided' do
      it 'restores from latest checkpoint' do
        checkpoint_id = manager.create_checkpoint('node-4', {})
        
        result = manager.restore_from_checkpoint(nil)

        expect(result).to be true
        workflow_run.reload
        expect(workflow_run.metadata['restored_from_checkpoint']).to eq(checkpoint_id)
      end
    end

    context 'when restoration fails' do
      it 'logs error and returns false' do
        allow(manager).to receive(:restore_workflow_state).and_raise(StandardError, 'Test error')

        expect(Rails.logger).to receive(:error).with(/Failed to restore from checkpoint/)
        
        result = manager.restore_from_checkpoint(checkpoint_id)
        expect(result).to be false
      end
    end
  end

  describe '#load_checkpoint' do
    it 'loads checkpoint from cache' do
      checkpoint_id = manager.create_checkpoint('node-5', { data: 'test' })

      loaded = manager.load_checkpoint(checkpoint_id)

      expect(loaded).to be_present
      expect(loaded['id']).to eq(checkpoint_id)
      expect(loaded['data']).to include(data: 'test')
    end

    it 'returns nil for non-existent checkpoint' do
      loaded = manager.load_checkpoint('non-existent-id')

      expect(loaded).to be_nil
    end
  end

  describe '#find_latest_checkpoint' do
    context 'when checkpoints exist' do
      it 'returns the most recent checkpoint' do
        checkpoint_id_1 = manager.create_checkpoint('node-6', {})
        sleep 0.01 # Ensure different timestamps
        checkpoint_id_2 = manager.create_checkpoint('node-7', {})

        latest = manager.find_latest_checkpoint

        expect(latest).to be_present
        expect(latest['id']).to eq(checkpoint_id_2)
      end
    end

    context 'when no checkpoints exist' do
      it 'returns nil' do
        # Clear any existing checkpoints
        workflow_run.update!(metadata: {})
        
        latest = manager.find_latest_checkpoint

        expect(latest).to be_nil
      end
    end
  end

  describe 'private methods' do
    describe '#capture_workflow_state' do
      it 'captures current workflow status' do
        state = manager.send(:capture_workflow_state)

        expect(state['run_status']).to eq('running')
        expect(state['current_node_id']).to eq(workflow_run.current_node_id)
        expect(state['execution_mode']).to be_present
        expect(state['runtime_context']).to eq(workflow_run.runtime_context)
      end
    end

    describe '#mark_nodes_as_completed' do
      # Use the last node to avoid conflicts with the before block
      let(:node) { workflow.ai_workflow_nodes.last }

      it 'creates execution records for completed nodes' do
        expect {
          manager.send(:mark_nodes_as_completed, [node.node_id])
        }.to change { workflow_run.ai_workflow_node_executions.count }.by(1)
      end

      it 'skips nodes that already have executions' do
        # First node already has an execution from before block
        existing_node = workflow.ai_workflow_nodes.first

        expect {
          manager.send(:mark_nodes_as_completed, [existing_node.node_id])
        }.not_to change { workflow_run.ai_workflow_node_executions.count }
      end

      it 'marks restored executions with skip flag' do
        manager.send(:mark_nodes_as_completed, [node.node_id])

        execution = workflow_run.ai_workflow_node_executions.find_by(node_id: node.node_id)
        expect(execution.output_data['skipped']).to be true
        expect(execution.output_data['reason']).to eq('restored_from_checkpoint')
      end

      it 'handles blank node ID array' do
        expect {
          manager.send(:mark_nodes_as_completed, [])
        }.not_to raise_error
      end
    end

    describe '#checkpoint_cache_key' do
      it 'generates correct cache key format' do
        checkpoint_id = SecureRandom.uuid
        cache_key = manager.send(:checkpoint_cache_key, checkpoint_id)

        expect(cache_key).to eq("workflow_checkpoint:#{workflow_run.id}:#{checkpoint_id}")
      end
    end
  end
end
