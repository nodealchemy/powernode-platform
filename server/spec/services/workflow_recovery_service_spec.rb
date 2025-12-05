# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowRecoveryService, type: :service do
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
      status: 'running'
    )
  end
  let(:service) { described_class.new(workflow_run: workflow_run, account: account, user: user) }

  before do
    # Stub logging to avoid expectations on unstubbed logger
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    # Stub ActionCable broadcasting
    stub_action_cable_broadcasting
  end

  describe '#initialize' do
    it 'initializes with workflow run and context' do
      expect(service.workflow_run).to eq(workflow_run)
      expect(service.account).to eq(account)
      expect(service.user).to eq(user)
      expect(service.logger).to be_present
    end

    it 'determines recovery strategy on initialization' do
      expect(service.instance_variable_get(:@recovery_strategy)).to be_present
    end

    it 'initializes empty checkpoints hash' do
      checkpoints = service.instance_variable_get(:@checkpoints)
      expect(checkpoints).to eq({})
    end
  end

  describe '#create_checkpoint' do
    let(:node) { workflow.ai_workflow_nodes.first }
    let(:checkpoint_data) { { step: 1, progress: 50 } }

    before do
      # Create some completed node executions
      create_list(:ai_workflow_node_execution, 2, :completed,
        ai_workflow_run: workflow_run
      )
    end

    it 'creates a checkpoint with unique ID' do
      checkpoint_id = service.create_checkpoint(node.node_id, checkpoint_data)

      expect(checkpoint_id).to be_present
      expect(checkpoint_id).to match(/\A[0-9a-f-]{36}\z/) # UUID format
    end

    it 'captures current workflow state' do
      checkpoint_id = service.create_checkpoint(node.node_id, checkpoint_data)
      checkpoint = service.send(:load_checkpoint, checkpoint_id)

      expect(checkpoint['workflow_run_id']).to eq(workflow_run.id)
      expect(checkpoint['node_id']).to eq(node.node_id)
      expect(checkpoint['state']).to be_present
      expect(checkpoint['created_at']).to be_present
    end

    it 'stores completed nodes in checkpoint' do
      checkpoint_id = service.create_checkpoint(node.node_id, checkpoint_data)
      checkpoint = service.send(:load_checkpoint, checkpoint_id)

      expect(checkpoint['completed_nodes']).to be_an(Array)
      expect(checkpoint['completed_nodes'].count).to eq(2)
    end

    it 'includes runtime variables in checkpoint' do
      workflow_run.update!(
        runtime_context: { 'variables' => { 'key' => 'value' } }
      )

      checkpoint_id = service.create_checkpoint(node.node_id, checkpoint_data)
      checkpoint = service.send(:load_checkpoint, checkpoint_id)

      expect(checkpoint['variables']).to eq({ 'key' => 'value' })
    end

    it 'stores custom checkpoint data' do
      checkpoint_id = service.create_checkpoint(node.node_id, checkpoint_data)
      checkpoint = service.send(:load_checkpoint, checkpoint_id)

      expect(checkpoint['data']).to eq(checkpoint_data)
    end

    it 'logs checkpoint creation' do
      expect(Rails.logger).to receive(:info)
        .with(/Created checkpoint.*at node #{node.node_id}/)

      service.create_checkpoint(node.node_id, checkpoint_data)
    end
  end

  describe '#restore_from_checkpoint' do
    let(:node) { workflow.ai_workflow_nodes.first }
    let(:checkpoint_data) { { step: 2, progress: 75 } }
    let(:checkpoint_id) { service.create_checkpoint(node.node_id, checkpoint_data) }

    context 'when checkpoint exists' do
      it 'restores workflow state from checkpoint' do
        # Delegation pattern: calls checkpoint_manager.restore_from_checkpoint
        expect_any_instance_of(Mcp::WorkflowCheckpointManager).to receive(:restore_from_checkpoint)
          .with(checkpoint_id).and_return(true)
        allow(service).to receive(:resume_from_checkpoint)

        result = service.restore_from_checkpoint(checkpoint_id)

        expect(result).to be_truthy
      end

      it 'updates workflow run metadata with restoration info' do
        # Metadata update happens in CheckpointManager, verify it's persisted
        allow(service).to receive(:resume_from_checkpoint)

        service.restore_from_checkpoint(checkpoint_id)

        workflow_run.reload
        expect(workflow_run.metadata['restored_from_checkpoint']).to eq(checkpoint_id)
      end

      it 'resumes execution from checkpoint' do
        allow(service).to receive(:restore_workflow_state)
        expect(service).to receive(:resume_from_checkpoint)
          .with(hash_including('id' => checkpoint_id))

        service.restore_from_checkpoint(checkpoint_id)
      end

      it 'logs restoration success' do
        allow(service).to receive(:restore_workflow_state)
        allow(service).to receive(:resume_from_checkpoint)

        expect(Rails.logger).to receive(:info)
          .with(/Restoring from checkpoint #{checkpoint_id}/)

        service.restore_from_checkpoint(checkpoint_id)
      end

      it 'returns true on successful restoration' do
        allow(service).to receive(:restore_workflow_state)
        allow(service).to receive(:resume_from_checkpoint)

        result = service.restore_from_checkpoint(checkpoint_id)

        expect(result).to be true
      end
    end

    context 'when checkpoint does not exist' do
      it 'logs warning and returns false' do
        expect(Rails.logger).to receive(:warn)
          .with(/No checkpoint found for restoration/)

        result = service.restore_from_checkpoint('non-existent-id')

        expect(result).to be false
      end
    end

    context 'when no checkpoint ID provided' do
      before do
        # Create multiple checkpoints
        3.times { |i| service.create_checkpoint(node.node_id, { step: i }) }
      end

      it 'restores from latest checkpoint' do
        # Delegation pattern: CheckpointManager handles finding latest
        allow(service).to receive(:resume_from_checkpoint)

        result = service.restore_from_checkpoint(nil)

        expect(result).to be_truthy
        workflow_run.reload
        expect(workflow_run.metadata['restored_from_checkpoint']).to be_present
      end
    end

    context 'when restoration fails' do
      before do
        # Make CheckpointManager return false to simulate failure
        allow_any_instance_of(Mcp::WorkflowCheckpointManager).to receive(:restore_from_checkpoint)
          .and_return(false)
      end

      it 'logs error and returns false' do
        result = service.restore_from_checkpoint(checkpoint_id)

        expect(result).to be false
      end
    end
  end

  describe '#retry_with_backoff' do
    let(:node_execution) do
      create(:ai_workflow_node_execution,
        ai_workflow_run: workflow_run,
        status: 'failed',
        error_details: { message: 'Temporary failure', type: 'temporary_error' }
      )
    end

    context 'when retry succeeds' do
      before do
        allow(service).to receive(:execute_node_retry)
          .and_return(create(:ai_workflow_node_execution, :completed))
      end

      it 'retries the failed node execution' do
        expect(service).to receive(:execute_node_retry).with(node_execution)

        service.retry_with_backoff(node_execution, max_attempts: 3)
      end

      it 'returns the successful execution' do
        result = service.retry_with_backoff(node_execution, max_attempts: 3)

        expect(result).to be_an(AiWorkflowNodeExecution)
        expect(result.status).to eq('completed')
      end

      it 'uses exponential backoff between retries' do
        call_count = 0
        allow(service).to receive(:execute_node_retry) do
          call_count += 1
          if call_count < 3
            raise StandardError, 'Still failing'
          else
            create(:ai_workflow_node_execution, :completed)
          end
        end

        expect(service).to receive(:sleep).with(1).ordered
        expect(service).to receive(:sleep).with(2).ordered

        service.retry_with_backoff(node_execution, max_attempts: 3)
      end
    end

    context 'when all retries fail' do
      before do
        allow(service).to receive(:execute_node_retry)
          .and_raise(StandardError, 'Persistent failure')
      end

      it 'respects max attempts limit' do
        max_attempts = 3
        expect(service).to receive(:execute_node_retry).exactly(max_attempts).times

        service.retry_with_backoff(node_execution, max_attempts: max_attempts)
      end

      it 'logs retry failures' do
        expect(Rails.logger).to receive(:warn).at_least(:once)
          .with(/Retry attempt.*failed/)

        service.retry_with_backoff(node_execution, max_attempts: 2)
      end

      it 'returns the failed execution' do
        result = service.retry_with_backoff(node_execution, max_attempts: 2)

        expect(result.status).to eq('failed')
      end
    end

    context 'with different backoff strategies' do
      it 'supports linear backoff' do
        allow(service).to receive(:execute_node_retry)
          .and_raise(StandardError).exactly(3).times

        # Only 2 sleeps occur (after attempts 1 and 2, not after final attempt 3)
        expect(service).to receive(:sleep).with(1).ordered
        expect(service).to receive(:sleep).with(2).ordered

        service.retry_with_backoff(node_execution,
          max_attempts: 3,
          backoff_strategy: :linear
        )
      end

      it 'supports exponential backoff' do
        allow(service).to receive(:execute_node_retry)
          .and_raise(StandardError).exactly(3).times

        # Only 2 sleeps occur (exponential: delay * 2^(attempt-1))
        # Attempt 1: sleep(1 * 2^0) = sleep(1)
        # Attempt 2: sleep(1 * 2^1) = sleep(2)
        expect(service).to receive(:sleep).with(1).ordered
        expect(service).to receive(:sleep).with(2).ordered

        service.retry_with_backoff(node_execution,
          max_attempts: 3,
          backoff_strategy: :exponential
        )
      end
    end
  end

  describe '#capture_workflow_state' do
    before do
      # Setup workflow with some executions
      create(:ai_workflow_node_execution, :completed,
        ai_workflow_run: workflow_run,
        output_data: { result: 'step 1 complete' }
      )
      create(:ai_workflow_node_execution, :running,
        ai_workflow_run: workflow_run
      )
    end

    it 'captures current workflow run status' do
      state = service.send(:capture_workflow_state)

      expect(state[:run_status]).to eq('running')
    end

    it 'captures execution progress' do
      workflow_run.update!(metadata: { 'progress_percentage' => 65 })
      state = service.send(:capture_workflow_state)

      expect(state[:progress]).to eq(65)
    end

    it 'captures node execution statuses' do
      state = service.send(:capture_workflow_state)

      expect(state[:node_statuses]).to include(
        'completed' => 1,
        'running' => 1
      )
    end

    it 'captures runtime context' do
      workflow_run.update!(
        runtime_context: { 'custom_data' => 'value' }
      )
      state = service.send(:capture_workflow_state)

      expect(state[:runtime_context]).to eq({ 'custom_data' => 'value' })
    end
  end

  describe '#determine_recovery_strategy' do
    it 'returns checkpoint strategy for long-running workflows' do
      workflow_run.update!(
        started_at: 2.hours.ago,
        status: 'running'
      )

      strategy = service.send(:determine_recovery_strategy)

      expect(strategy).to eq(:checkpoint_based)
    end

    it 'returns retry strategy for quick workflows' do
      workflow_run.update!(
        started_at: 30.seconds.ago,
        completed_at: Time.current,
        status: 'failed',
        error_details: { message: 'Workflow failed', type: 'temporary_error' }
      )

      strategy = service.send(:determine_recovery_strategy)

      expect(strategy).to eq(:node_retry)
    end

    it 'returns graceful degradation for critical errors' do
      workflow_run.update!(
        status: 'failed',
        completed_at: Time.current,
        error_details: { message: 'Critical system error', type: 'critical_error' }
      )

      strategy = service.send(:determine_recovery_strategy)

      expect(strategy).to eq(:graceful_degradation)
    end
  end

  # NOTE: Private checkpoint storage methods (#store_checkpoint, #load_checkpoint, #find_latest_checkpoint)
  # are now delegated to Mcp::WorkflowCheckpointManager and tested comprehensively in
  # spec/services/mcp/workflow_checkpoint_manager_spec.rb (26/26 tests passing)

  describe 'recovery execution' do
    describe '#restore_workflow_state' do
      let(:checkpoint) do
        {
          id: SecureRandom.uuid,
          state: { run_status: 'paused', progress: 50 },
          variables: { 'count' => 5 },
          output_data: { 'result' => 'partial' },
          completed_nodes: ['node-1', 'node-2']
        }.with_indifferent_access
      end

      it 'restores workflow run state' do
        service.send(:restore_workflow_state, checkpoint)

        workflow_run.reload
        expect(workflow_run.runtime_context['variables']).to eq({ 'count' => 5 })
      end

      it 'restores output variables' do
        service.send(:restore_workflow_state, checkpoint)

        workflow_run.reload
        expect(workflow_run.output_variables).to include('result' => 'partial')
      end

      it 'marks completed nodes as skipped in new execution' do
        allow(service).to receive(:mark_nodes_as_completed)

        service.send(:restore_workflow_state, checkpoint)

        expect(service).to have_received(:mark_nodes_as_completed)
          .with(['node-1', 'node-2'])
      end
    end

    describe '#resume_from_checkpoint' do
      let(:resume_node) { workflow.ai_workflow_nodes.second } # Use actual workflow node
      let(:checkpoint) do
        {
          id: SecureRandom.uuid,
          node_id: resume_node.node_id,
          state: { run_status: 'paused' },
          variables: { 'resume_point' => 'step_3' }
        }.with_indifferent_access
      end

      it 'identifies the next node to execute' do
        next_node = service.send(:find_next_node_after_checkpoint, checkpoint)

        expect(next_node).to be_present
      end

      it 'continues execution from checkpoint node' do
        expect(service).to receive(:execute_workflow_from_node)
          .with(resume_node.node_id, hash_including('resume_point' => 'step_3'))

        service.send(:resume_from_checkpoint, checkpoint)
      end

      it 'logs resumption' do
        # Mock workflow execution to prevent timeout
        allow(service).to receive(:execute_workflow_from_node)

        expect(Rails.logger).to receive(:info)
          .with(/Resuming execution from node: #{resume_node.node_id}/)

        service.send(:resume_from_checkpoint, checkpoint)
      end
    end
  end

  describe 'error recovery strategies' do
    describe 'checkpoint-based recovery' do
      it 'creates checkpoints at key execution points' do
        service.instance_variable_set(:@recovery_strategy, :checkpoint_based)
        workflow_run.update!(current_node_id: 'test-node-id')

        expect(service).to receive(:create_checkpoint).at_least(:once)

        service.send(:apply_checkpoint_recovery_strategy)
      end

      it 'restores from last successful checkpoint on failure' do
        checkpoint_id = service.create_checkpoint('node-1', {})
        workflow_run.update!(
          status: 'failed',
          completed_at: Time.current,
          error_details: { 'message' => 'Test failure', 'type' => 'test_error' }
        )

        service.send(:apply_checkpoint_recovery_strategy)

        # Verify restoration happened (apply_checkpoint_recovery_strategy creates its own checkpoint,
        # so restored_from_checkpoint will be different from the one we created manually)
        expect(workflow_run.reload.metadata['restored_from_checkpoint']).to be_present
      end
    end

    describe 'node retry recovery' do
      let(:failed_execution) do
        create(:ai_workflow_node_execution, :failed,
          ai_workflow_run: workflow_run
        )
      end

      it 'retries failed nodes with backoff' do
        service.instance_variable_set(:@recovery_strategy, :node_retry)

        expect(service).to receive(:retry_with_backoff)
          .with(failed_execution, max_attempts: 3)

        service.send(:apply_node_retry_strategy, failed_execution)
      end
    end

    describe 'graceful degradation' do
      it 'skips failed non-critical nodes' do
        service.instance_variable_set(:@recovery_strategy, :graceful_degradation)

        non_critical_node = workflow.ai_workflow_nodes.find_by(
          configuration: hash_including('critical' => false)
        ) || create(:ai_workflow_node, ai_workflow: workflow,
                   configuration: { 'critical' => false })

        result = service.send(:apply_graceful_degradation, non_critical_node)

        expect(result[:action]).to eq('skip')
      end

      it 'fails fast on critical node failures' do
        service.instance_variable_set(:@recovery_strategy, :graceful_degradation)

        critical_node = workflow.ai_workflow_nodes.find_by(
          configuration: hash_including('critical' => true)
        ) || create(:ai_workflow_node, ai_workflow: workflow,
                   configuration: { 'critical' => true })

        result = service.send(:apply_graceful_degradation, critical_node)

        expect(result[:action]).to eq('fail_fast')
      end
    end
  end

  describe 'integration with MCP checkpoint manager' do
    let(:mcp_services) { stub_mcp_services }

    it 'delegates checkpoint creation to MCP manager' do
      mcp_manager = instance_double('Mcp::WorkflowCheckpointManager')
      allow(Mcp::WorkflowCheckpointManager).to receive(:new).and_return(mcp_manager)
      allow(mcp_manager).to receive(:create_checkpoint).and_return('checkpoint-id')

      service.create_checkpoint('node-id', {})

      expect(mcp_manager).to have_received(:create_checkpoint)
    end

    it 'delegates checkpoint restoration to MCP manager' do
      mcp_manager = instance_double('Mcp::WorkflowCheckpointManager')
      checkpoint_data = { 'id' => 'checkpoint-id', 'node_id' => 'node-id' }

      allow(Mcp::WorkflowCheckpointManager).to receive(:new).and_return(mcp_manager)
      allow(mcp_manager).to receive(:create_checkpoint).and_return('checkpoint-id')
      allow(mcp_manager).to receive(:restore_from_checkpoint).and_return(true)
      allow(mcp_manager).to receive(:load_checkpoint).and_return(checkpoint_data)
      allow(service).to receive(:resume_from_checkpoint) # Prevent actual workflow execution

      checkpoint_id = service.create_checkpoint('node-id', {})
      service.restore_from_checkpoint(checkpoint_id)

      expect(mcp_manager).to have_received(:restore_from_checkpoint)
    end
  end
end
