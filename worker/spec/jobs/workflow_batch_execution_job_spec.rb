# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowBatchExecutionJob, type: :job do
  subject { described_class }

  # Test data needed by shared examples
  let(:workflow_id) { 'workflow-123' }
  let(:batch_id) { 'batch-456' }
  let(:workflow_job_args) { { workflow_id: workflow_id, batch_id: batch_id } }

  # Shared examples for base job behavior
  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:job_instance) { described_class.new }
  let(:user_id) { 'user-789' }
  let(:run_id) { 'run-101' }
  let(:api_client_double) { double('BackendApiClient') }

  let(:execution_options) {
    {
      'trigger_type' => 'batch',
      'input_variables' => {
        'param1' => 'value1',
        'param2' => 'value2'
      },
      'wait_for_completion' => false
    }
  }

  let(:workflow_data) {
    {
      'workflow' => {
        'id' => workflow_id,
        'name' => 'Test Workflow',
        'version' => '1.0.0',
        'status' => 'active'
      }
    }
  }

  let(:workflow_run_data) {
    {
      'run_id' => run_id,
      'workflow_id' => workflow_id,
      'status' => 'queued',
      'created_at' => Time.current.iso8601
    }
  }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with correct queue' do
      expect(described_class.get_sidekiq_options['queue'].to_s).to eq('workflow_high_priority')
    end
  end

  describe '#execute' do
    context 'with successful workflow execution' do
      before do
        # Stub workflow data fetch
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        # Stub workflow run creation
        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => true,
            'data' => workflow_run_data
          })

        # Stub workflow execution
        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs/#{run_id}/execute", anything)
          .and_return({ 'success' => true })

        # Stub batch progress update
        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })
      end

      it 'executes workflow successfully' do
        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            user_id: user_id,
            execution_options: execution_options
          )
        }.not_to raise_error

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/ai/workflow_runs/#{run_id}/execute", {})
      end

      it 'creates workflow run with batch metadata' do
        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          user_id: user_id,
          execution_options: execution_options
        )

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/ai/workflow_runs", hash_including(
            workflow_id: workflow_id,
            trigger_type: 'batch',
            metadata: hash_including(
              batch_id: batch_id,
              execution_options: execution_options
            )
          ))
      end

      it 'includes input variables from execution options' do
        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/ai/workflow_runs", hash_including(
            input_variables: hash_including(
              'param1' => 'value1',
              'param2' => 'value2'
            )
          ))
      end

      it 'updates batch progress with success' do
        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(api_client_double).to have_received(:patch)
          .with("/api/v1/ai/batch_runs/#{batch_id}/progress", hash_including(
            workflow_id: workflow_id,
            success: true,
            error: nil
          ))
      end

      it 'logs job completion' do
        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(logger_double).to have_received(:info)
          .with(a_string_matching(/Completed workflow #{workflow_id} in batch #{batch_id}/))
      end

      it 'defaults trigger_type to batch if not provided' do
        options_without_trigger = execution_options.dup
        options_without_trigger.delete('trigger_type')

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: options_without_trigger
        )

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/ai/workflow_runs", hash_including(
            trigger_type: 'batch'
          ))
      end

      it 'defaults input_variables to empty hash if not provided' do
        options_without_input = { 'trigger_type' => 'batch' }

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: options_without_input
        )

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/ai/workflow_runs", hash_including(
            input_variables: {}
          ))
      end
    end

    context 'with workflow not found' do
      before do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => false,
            'error' => 'Workflow not found'
          })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })
      end

      it 'handles workflow not found gracefully' do
        # Stub post method as spy to verify it's not called
        allow(api_client_double).to receive(:post)

        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.not_to raise_error

        # Should not attempt to create run or execute
        expect(api_client_double).not_to have_received(:post).with("/api/v1/ai/workflow_runs", anything)
      end

      it 'updates batch progress with failure' do
        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(api_client_double).to have_received(:patch)
          .with("/api/v1/ai/batch_runs/#{batch_id}/progress", hash_including(
            success: false,
            error: 'Workflow not found'
          ))
      end

      it 'logs workflow not found error' do
        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Workflow #{workflow_id} not found/))
      end
    end

    context 'with workflow run creation failure' do
      before do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => false,
            'error' => 'Failed to create workflow run'
          })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })
      end

      it 'handles run creation failure gracefully' do
        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.not_to raise_error

        # Should not attempt to execute workflow
        expect(api_client_double).not_to have_received(:post).with(/workflow_runs\/#{run_id}\/execute/)
      end

      it 'updates batch progress with failure' do
        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(api_client_double).to have_received(:patch)
          .with("/api/v1/ai/batch_runs/#{batch_id}/progress", hash_including(
            success: false,
            error: 'Failed to create workflow run'
          ))
      end

      it 'logs run creation failure' do
        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Failed to create workflow run/))
          .at_least(:once)
      end
    end

    context 'with workflow execution failure' do
      before do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => true,
            'data' => workflow_run_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs/#{run_id}/execute", anything)
          .and_return({
            'success' => false,
            'error' => 'Workflow execution failed'
          })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })
      end

      it 'raises error on workflow execution failure' do
        logger_double = mock_logger

        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.to raise_error(RuntimeError, /Workflow execution failed/)

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Error executing workflow/))
      end

      it 'updates batch progress with failure before re-raising' do
        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.to raise_error(RuntimeError)

        expect(api_client_double).to have_received(:patch)
          .with("/api/v1/ai/batch_runs/#{batch_id}/progress", hash_including(
            success: false,
            error: a_string_matching(/Workflow execution failed/)
          ))
      end
    end

    context 'with wait_for_completion enabled' do
      let(:wait_options) {
        execution_options.merge('wait_for_completion' => true)
      }

      before do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => true,
            'data' => workflow_run_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs/#{run_id}/execute", anything)
          .and_return({ 'success' => true })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })
      end

      it 'monitors workflow execution until completion' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return(
            { 'success' => true, 'data' => { 'status' => 'running' } },
            { 'success' => true, 'data' => { 'status' => 'running' } },
            { 'success' => true, 'data' => { 'status' => 'completed' } }
          )

        allow(job_instance).to receive(:sleep) # Skip actual sleep in tests

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(api_client_double).to have_received(:get)
          .with("/api/v1/ai/workflow_runs/#{run_id}")
          .at_least(3).times
      end

      it 'logs workflow completion' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return({ 'success' => true, 'data' => { 'status' => 'completed' } })

        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(logger_double).to have_received(:info)
          .with(a_string_matching(/Workflow #{run_id} completed successfully/))
      end

      it 'detects workflow failure' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return({ 'success' => true, 'data' => { 'status' => 'failed' } })

        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Workflow #{run_id} failed with status: failed/))
      end

      it 'detects workflow cancellation' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return({ 'success' => true, 'data' => { 'status' => 'cancelled' } })

        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Workflow #{run_id} failed with status: cancelled/))
      end

      it 'times out after max attempts' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return({ 'success' => true, 'data' => { 'status' => 'running' } })

        allow(job_instance).to receive(:sleep) # Skip actual sleep

        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Workflow #{run_id} execution timeout/))

        # Should make 60 attempts (max_attempts)
        expect(api_client_double).to have_received(:get)
          .with("/api/v1/ai/workflow_runs/#{run_id}")
          .exactly(60).times
      end

      it 'continues waiting for initializing status' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return(
            { 'success' => true, 'data' => { 'status' => 'initializing' } },
            { 'success' => true, 'data' => { 'status' => 'running' } },
            { 'success' => true, 'data' => { 'status' => 'completed' } }
          )

        allow(job_instance).to receive(:sleep)

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(api_client_double).to have_received(:get)
          .with("/api/v1/ai/workflow_runs/#{run_id}")
          .at_least(3).times
      end

      it 'handles unknown workflow status' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return(
            { 'success' => true, 'data' => { 'status' => 'unknown_status' } },
            { 'success' => true, 'data' => { 'status' => 'completed' } }
          )

        allow(job_instance).to receive(:sleep)
        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(logger_double).to have_received(:warn)
          .with(a_string_matching(/Unknown workflow status: unknown_status/))
      end

      it 'handles status check API errors' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflow_runs/#{run_id}")
          .and_return(
            { 'success' => false, 'error' => 'API error' },
            { 'success' => true, 'data' => { 'status' => 'completed' } }
          )

        allow(job_instance).to receive(:sleep)
        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: wait_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Failed to check workflow status/))
      end
    end

    context 'with API errors' do
      before do
        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })
      end

      it 'handles fetch workflow API exception' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_raise(StandardError.new('Connection timeout'))

        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/API error fetching workflow/))
      end

      it 'handles create run API exception' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_raise(StandardError.new('Connection timeout'))

        logger_double = mock_logger

        job_instance.execute(
          workflow_id: workflow_id,
          batch_id: batch_id,
          execution_options: execution_options
        )

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/API error creating workflow run/))
      end

      it 'handles batch progress update failures gracefully' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => true,
            'data' => workflow_run_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs/#{run_id}/execute", anything)
          .and_return({ 'success' => true })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_raise(StandardError.new('Update failed'))

        logger_double = mock_logger

        # Should not raise error even if batch update fails
        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.not_to raise_error

        expect(logger_double).to have_received(:error)
          .with(a_string_matching(/Error updating batch progress/))
      end

      it 'logs backtrace on StandardError' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_raise(StandardError.new('Test error'))

        # Stub patch to prevent additional API calls
        allow(api_client_double).to receive(:patch)
          .and_return({ 'success' => true })

        logger_double = mock_logger

        # API errors in fetch methods are caught and handled gracefully
        # The job should not raise, but should log the error
        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.not_to raise_error

        # Should log the API error from fetch_workflow_data
        expect(logger_double).to have_received(:error)
          .with(a_string_including('API error fetching workflow'))
          .at_least(:once)
      end
    end

    context 'with optional parameters' do
      it 'works without user_id' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => true,
            'data' => workflow_run_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs/#{run_id}/execute", anything)
          .and_return({ 'success' => true })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })

        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: execution_options
          )
        }.not_to raise_error
      end

      it 'works with empty execution_options' do
        allow(api_client_double).to receive(:get).with("/api/v1/ai/workflows/#{workflow_id}")
          .and_return({
            'success' => true,
            'data' => workflow_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs", anything)
          .and_return({
            'success' => true,
            'data' => workflow_run_data
          })

        allow(api_client_double).to receive(:post).with("/api/v1/ai/workflow_runs/#{run_id}/execute", anything)
          .and_return({ 'success' => true })

        allow(api_client_double).to receive(:patch).with("/api/v1/ai/batch_runs/#{batch_id}/progress", anything)
          .and_return({ 'success' => true })

        expect {
          job_instance.execute(
            workflow_id: workflow_id,
            batch_id: batch_id,
            execution_options: {}
          )
        }.not_to raise_error
      end
    end
  end
end
