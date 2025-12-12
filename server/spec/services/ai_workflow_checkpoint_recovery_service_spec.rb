# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowCheckpointRecoveryService do
  # Stub ActionCable broadcast to prevent NameError in tests
  before do
    stub_const('AiWorkflowExecutionChannel', Class.new do
      def self.broadcast_run_status(*args); end
    end)
  end

  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }
  let(:workflow_run) do
    run = create(:ai_workflow_run, :failed,
           ai_workflow: workflow,
           account: account,
           input_variables: { 'input_data' => 'test' },
           output_variables: { 'result' => 'partial' },
           runtime_context: { 'user_id' => '123' })
    # Set total/completed nodes after creation to ensure they persist
    run.update!(total_nodes: 10, completed_nodes: 5)
    run
  end

  describe '#create_checkpoint' do
    let(:service) { described_class.new(workflow_run: workflow_run) }

    context 'with valid checkpoint type' do
      it 'creates a checkpoint with correct data' do
        checkpoint = service.create_checkpoint(
          type: 'node_completion',
          node_id: 'node-5',
          metadata: { custom: 'data' }
        )

        expect(checkpoint).to be_persisted
        expect(checkpoint.checkpoint_type).to eq('node_completion')
        expect(checkpoint.node_id).to eq('node-5')
        expect(checkpoint.sequence_number).to eq(1)
      end

      it 'captures complete state snapshot' do
        checkpoint = service.create_checkpoint(
          type: 'node_completion',
          node_id: 'node-5'
        )

        expect(checkpoint.variable_snapshot).to be_present
        expect(checkpoint.workflow_state['completed_nodes']).to be_an(Array)
        expect(checkpoint.execution_context).to be_present
        expect(checkpoint.workflow_state['execution_path']).to be_an(Array)
      end

      it 'captures workflow metadata' do
        checkpoint = service.create_checkpoint(
          type: 'node_completion',
          node_id: 'node-5'
        )

        metadata = checkpoint.metadata
        expect(metadata['workflow_version']).to eq(workflow.version)
        expect(metadata['total_nodes']).to eq(workflow_run.total_nodes)
        expect(metadata['completed_nodes']).to eq(workflow_run.completed_nodes)
        expect(metadata['progress_percentage']).to be_a(Numeric)
      end

      it 'increments sequence number for subsequent checkpoints' do
        first = service.create_checkpoint(type: 'node_completion', node_id: 'node-1')
        second = service.create_checkpoint(type: 'node_completion', node_id: 'node-2')
        third = service.create_checkpoint(type: 'node_completion', node_id: 'node-3')

        expect(first.sequence_number).to eq(1)
        expect(second.sequence_number).to eq(2)
        expect(third.sequence_number).to eq(3)
      end

      it 'includes custom metadata' do
        checkpoint = service.create_checkpoint(
          type: 'manual_checkpoint',
          node_id: 'node-5',
          metadata: { reason: 'before_expensive_operation', user: 'admin' }
        )

        custom = checkpoint.metadata['custom']
        expect(custom['reason']).to eq('before_expensive_operation')
        expect(custom['user']).to eq('admin')
      end
    end

    context 'with invalid checkpoint type' do
      it 'raises ArgumentError' do
        expect {
          service.create_checkpoint(type: 'invalid_type', node_id: 'node-1')
        }.to raise_error(ArgumentError, /Invalid checkpoint type/)
      end
    end

    context 'checkpoint cleanup' do
      it 'keeps only last 10 checkpoints' do
        15.times do |i|
          service.create_checkpoint(type: 'node_completion', node_id: "node-#{i}")
        end

        expect(workflow_run.ai_workflow_checkpoints.count).to eq(10)
      end

      it 'deletes oldest checkpoints first' do
        15.times do |i|
          service.create_checkpoint(type: 'node_completion', node_id: "node-#{i}")
        end

        remaining = workflow_run.ai_workflow_checkpoints.order(:sequence_number).pluck(:sequence_number)
        expect(remaining).to eq((6..15).to_a)
      end
    end
  end

  describe '#restore_from_checkpoint' do
    let!(:checkpoint) do
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'node_completion',
        node_id: 'node-5',
        sequence_number: 1,
        workflow_state: {
          'status' => 'running',
          'completed_nodes' => [ 'node-1', 'node-2', 'node-3' ],
          'execution_path' => [ 'node-1', 'node-2', 'node-3' ]
        },
        execution_context: { 'session' => 'abc123' },
        variable_snapshot: { 'var1' => 'value1', 'var2' => 'value2' },
        metadata: {
          'progress_percentage' => 30.0,
          'cost_so_far' => 0.50,
          'duration_so_far' => 5000
        }
      )
    end

    let(:service) { described_class.new(workflow_run: workflow_run, checkpoint: checkpoint) }

    context 'with valid checkpoint' do
      it 'restores workflow to running status' do
        service.restore_from_checkpoint
        expect(workflow_run.reload.status).to eq('running')
      end

      it 'restores variables to runtime context' do
        service.restore_from_checkpoint

        context = workflow_run.reload.runtime_context
        expect(context['variables']['var1']).to eq('value1')
        expect(context['variables']['var2']).to eq('value2')
      end

      it 'restores output variables' do
        service.restore_from_checkpoint

        outputs = workflow_run.reload.output_variables
        expect(outputs['var1']).to eq('value1')
        expect(outputs['var2']).to eq('value2')
      end

      it 'marks completed nodes' do
        # Create workflow nodes that match the checkpoint data
        wf_node1 = create(:ai_workflow_node, ai_workflow: workflow, node_id: 'node-1')
        wf_node2 = create(:ai_workflow_node, ai_workflow: workflow, node_id: 'node-2')

        # Create node executions
        node1 = create(:ai_workflow_node_execution,
                      ai_workflow_run: workflow_run,
                      ai_workflow_node: wf_node1,
                      node_id: 'node-1',
                      node_type: wf_node1.node_type,
                      status: 'pending')

        node2 = create(:ai_workflow_node_execution,
                      ai_workflow_run: workflow_run,
                      ai_workflow_node: wf_node2,
                      node_id: 'node-2',
                      node_type: wf_node2.node_type,
                      status: 'pending')

        service.restore_from_checkpoint

        expect(node1.reload.status).to eq('completed')
        expect(node2.reload.status).to eq('completed')
      end

      it 'adds recovery metadata to workflow run' do
        service.restore_from_checkpoint

        metadata = workflow_run.reload.metadata
        expect(metadata['recovered_from_checkpoint']).to eq(checkpoint.id)
        expect(metadata['recovered_at']).to be_present
        expect(metadata['recovery_sequence']).to eq(1)
      end

      it 'adds recovery metadata to node executions' do
        # Create workflow node that matches checkpoint data
        wf_node = create(:ai_workflow_node, ai_workflow: workflow, node_id: 'node-1')

        node = create(:ai_workflow_node_execution,
                     ai_workflow_run: workflow_run,
                     ai_workflow_node: wf_node,
                     node_id: 'node-1',
                     node_type: wf_node.node_type,
                     status: 'pending')

        service.restore_from_checkpoint

        node_metadata = node.reload.metadata
        expect(node_metadata['restored_from_checkpoint']).to be true
        expect(node_metadata['checkpoint_id']).to eq(checkpoint.id)
      end

      it 'clears error details' do
        workflow_run.update(error_details: { error: 'something failed' })

        service.restore_from_checkpoint

        expect(workflow_run.reload.error_details).to eq({})
      end

      it 'sets recovery mode flag' do
        service.restore_from_checkpoint

        context = workflow_run.reload.runtime_context
        expect(context['recovery_mode']).to be true
      end

      it 'returns success result with statistics' do
        result = service.restore_from_checkpoint

        expect(result[:success]).to be true
        expect(result[:resumed_at]).to eq('node-5')
        expect(result[:resumed_position]).to eq(30.0)
        expect(result[:restored_variables]).to eq([ 'var1', 'var2' ])
        expect(result[:checkpoint_age_seconds]).to be >= 0
      end

      it 'performs restoration in transaction' do
        allow(workflow_run).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          service.restore_from_checkpoint
        }.not_to change { workflow_run.reload.status }
      end
    end

    context 'without checkpoint provided' do
      let(:service) { described_class.new(workflow_run: workflow_run) }

      it 'raises ArgumentError' do
        expect {
          service.restore_from_checkpoint
        }.to raise_error(ArgumentError, /No checkpoint provided/)
      end
    end

    context 'when restoration fails' do
      before do
        allow(workflow_run).to receive(:update!).and_raise(StandardError, 'Database error')
      end

      it 'returns failure result' do
        result = service.restore_from_checkpoint

        expect(result[:success]).to be false
        expect(result[:error]).to include('Database error')
      end

      it 'does not modify workflow state on error' do
        original_status = workflow_run.status
        service.restore_from_checkpoint

        expect(workflow_run.reload.status).to eq(original_status)
      end
    end
  end

  describe '.find_recovery_checkpoint' do
    let!(:node_checkpoint) do
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'node_completion',
        node_id: 'node-5',
        sequence_number: 5,
        workflow_state: { status: 'completed' },
        execution_context: { session: 'abc123' },
        created_at: 1.hour.ago
      )
    end

    let!(:manual_checkpoint) do
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'manual_checkpoint',
        node_id: 'node-3',
        sequence_number: 3,
        workflow_state: { status: 'paused' },
        execution_context: { session: 'abc123' },
        created_at: 2.hours.ago
      )
    end

    let!(:error_checkpoint) do
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'error_checkpoint',
        node_id: 'node-4',
        sequence_number: 4,
        workflow_state: { status: 'error' },
        execution_context: { session: 'abc123' },
        created_at: 1.5.hours.ago
      )
    end

    it 'prefers node_completed checkpoints' do
      checkpoint = described_class.find_recovery_checkpoint(workflow_run)
      expect(checkpoint.checkpoint_type).to eq('node_completion')
    end

    it 'returns most recent checkpoint if no node_completed' do
      node_checkpoint.destroy

      checkpoint = described_class.find_recovery_checkpoint(workflow_run)
      expect(checkpoint.sequence_number).to eq(4)
    end

    it 'ignores checkpoints older than retention period' do
      old_checkpoint = workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'node_completion',
        node_id: 'node-1',
        sequence_number: 1,
        workflow_state: { status: 'old' },
        execution_context: { session: 'xyz789' },
        created_at: 31.days.ago
      )

      checkpoint = described_class.find_recovery_checkpoint(workflow_run)
      expect(checkpoint).not_to eq(old_checkpoint)
    end

    it 'returns nil when no checkpoints available' do
      workflow_run.ai_workflow_checkpoints.destroy_all

      checkpoint = described_class.find_recovery_checkpoint(workflow_run)
      expect(checkpoint).to be_nil
    end
  end

  describe '.recoverable?' do
    context 'when workflow is failed with checkpoints' do
      before do
        workflow_run.update(status: 'failed')
        workflow_run.ai_workflow_checkpoints.create!(
          checkpoint_type: 'node_completion',
          node_id: 'node-1',
          sequence_number: 1,
          workflow_state: { status: 'completed' },
          execution_context: { session: 'test' }
        )
      end

      it 'returns true' do
        expect(described_class.recoverable?(workflow_run)).to be true
      end
    end

    context 'when workflow is cancelled with checkpoints' do
      before do
        workflow_run.update(status: 'cancelled')
        workflow_run.ai_workflow_checkpoints.create!(
          checkpoint_type: 'node_completion',
          node_id: 'node-1',
          sequence_number: 1,
          workflow_state: { status: 'completed' },
          execution_context: { session: 'test' }
        )
      end

      it 'returns true' do
        expect(described_class.recoverable?(workflow_run)).to be true
      end
    end

    context 'when workflow is running' do
      before do
        workflow_run.update(status: 'running')
        workflow_run.ai_workflow_checkpoints.create!(
          checkpoint_type: 'node_completion',
          node_id: 'node-1',
          sequence_number: 1,
          workflow_state: { status: 'completed' },
          execution_context: { session: 'test' }
        )
      end

      it 'returns false' do
        expect(described_class.recoverable?(workflow_run)).to be false
      end
    end

    context 'when no checkpoints exist' do
      before { workflow_run.update(status: 'failed') }

      it 'returns false' do
        expect(described_class.recoverable?(workflow_run)).to be false
      end
    end
  end

  describe '#recovery_stats' do
    let!(:checkpoint) do
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'node_completion',
        node_id: 'node-5',
        sequence_number: 3,
        workflow_state: {
          status: 'completed',
          completed_nodes: [ 'node-1', 'node-2', 'node-3' ]  # 3 out of 10 = 30%
        },
        execution_context: { session: 'test' },
        metadata: { progress_percentage: 30.0 },
        created_at: 2.minutes.ago
      )
    end

    let(:service) { described_class.new(workflow_run: workflow_run, checkpoint: checkpoint) }

    before do
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'manual_checkpoint',
        node_id: 'node-1',
        sequence_number: 1,
        workflow_state: { status: 'paused' },
        execution_context: { session: 'test' }
      )
      workflow_run.ai_workflow_checkpoints.create!(
        checkpoint_type: 'manual_checkpoint',
        node_id: 'node-2',
        sequence_number: 2,
        workflow_state: { status: 'paused' },
        execution_context: { session: 'test' }
      )
    end

    it 'returns comprehensive recovery statistics' do
      stats = service.recovery_stats

      expect(stats[:checkpoint_id]).to eq(checkpoint.id)
      expect(stats[:checkpoint_type]).to eq('node_completion')
      expect(stats[:checkpoint_age_seconds]).to be >= 0
      expect(stats[:checkpoint_node]).to eq('node-5')
      expect(stats[:sequence_number]).to eq(3)
      expect(stats[:total_checkpoints]).to eq(3)
      expect(stats[:recoverable]).to be true
      expect(stats[:estimated_resume_position]).to eq(30.0)
    end

    it 'returns empty hash when no checkpoint provided' do
      service_without_checkpoint = described_class.new(workflow_run: workflow_run)
      expect(service_without_checkpoint.recovery_stats).to eq({})
    end
  end

  describe 'state capture' do
    let(:service) { described_class.new(workflow_run: workflow_run) }

    context 'capturing variables' do
      before do
        workflow_run.update(
          input_variables: { 'input' => 'data' },
          output_variables: { 'output' => 'result' },
          runtime_context: { 'variables' => { 'runtime' => 'var' } }
        )
      end

      it 'merges all variable sources with correct precedence' do
        checkpoint = service.create_checkpoint(type: 'manual_checkpoint', node_id: 'test')

        variables = checkpoint.variable_snapshot
        expect(variables['input']).to eq('data')
        expect(variables['runtime']).to eq('var')
        expect(variables['output']).to eq('result')
      end

      it 'gives precedence to output over runtime over input' do
        workflow_run.update(
          input_variables: { 'key' => 'input_value' },
          runtime_context: { 'variables' => { 'key' => 'runtime_value' } },
          output_variables: { 'key' => 'output_value' }
        )

        checkpoint = service.create_checkpoint(type: 'manual_checkpoint', node_id: 'test')
        expect(checkpoint.variable_snapshot['key']).to eq('output_value')
      end
    end

    context 'capturing completed nodes' do
      before do
        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               node_id: 'node-1',
               status: 'completed')

        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               node_id: 'node-2',
               status: 'completed')

        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               node_id: 'node-3',
               status: 'failed')
      end

      it 'captures only completed node IDs' do
        checkpoint = service.create_checkpoint(type: 'manual_checkpoint', node_id: 'test')

        completed = checkpoint.workflow_state['completed_nodes']
        expect(completed).to contain_exactly('node-1', 'node-2')
      end
    end

    context 'capturing execution path' do
      before do
        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               node_id: 'node-1',
               status: 'completed',
               created_at: 3.minutes.ago)

        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               node_id: 'node-2',
               status: 'failed',
               created_at: 2.minutes.ago)

        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               node_id: 'node-3',
               status: 'completed',
               created_at: 1.minute.ago)
      end

      it 'captures execution path in chronological order' do
        checkpoint = service.create_checkpoint(type: 'manual_checkpoint', node_id: 'test')

        path = checkpoint.workflow_state['execution_path']
        expect(path).to eq([ 'node-1', 'node-2', 'node-3' ])
      end
    end
  end
end
