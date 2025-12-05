# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowExecutionJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:account_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }
  let(:workflow_id) { SecureRandom.uuid }
  let(:workflow_run_id) { SecureRandom.uuid }

  let(:workflow_run_data) do
    {
      'id' => workflow_run_id,
      'ai_workflow_id' => workflow_id,
      'workflow_id' => workflow_id,
      'account_id' => account_id,
      'user_id' => user_id,
      'status' => 'running',
      'input_variables' => { 'test' => 'value' },
      'started_at' => Time.current.iso8601
    }
  end

  let(:successful_execution_response) do
    {
      'success' => true,
      'data' => {
        'output_variables' => { 'result' => 'success' },
        'duration_ms' => 5000,
        'total_cost' => 0.25
      }
    }
  end

  let(:failed_execution_response) do
    {
      'success' => false,
      'error' => 'Node execution failed',
      'data' => { 'failed_node' => 'node_1' }
    }
  end

  let(:job_options) do
    {
      'realtime' => true,
      'channel_id' => "workflow_#{workflow_run_id}"
    }
  end

  describe '#execute' do
    let(:job) { described_class.new }

    context 'when workflow run is found and executes successfully' do
      before do
        # Stub workflow run lookup
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        # Stub workflow execution (direct HTTP call)
        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: successful_execution_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Stub status update
        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => true
        })

        # Stub broadcast
        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/broadcast", {
          'success' => true
        })
      end

      it 'fetches workflow run data' do
        job.execute(workflow_run_id, job_options)

        expect_api_request(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}")
      end

      it 'executes the workflow' do
        job.execute(workflow_run_id, job_options)

        expect(WebMock).to have_requested(:post, %r{/runs/#{workflow_run_id}/process})
      end

      it 'updates workflow status to completed' do
        job.execute(workflow_run_id, job_options)

        expect_api_request(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}")
      end

      it 'broadcasts status when realtime is enabled' do
        job.execute(workflow_run_id, job_options)

        expect(WebMock).to have_requested(:post, %r{/broadcast}).at_least_once
      end

      it 'logs successful completion' do
        capture_logs_for(job)

        job.execute(workflow_run_id, job_options)

        expect_logged(:info, /completed successfully/)
      end
    end

    context 'when workflow run is not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns early' do
        result = job.execute(workflow_run_id, job_options)

        expect(result).to be_nil
      end

      it 'logs error' do
        capture_logs_for(job)

        job.execute(workflow_run_id, job_options)

        expect_logged(:error, /Failed to fetch workflow run/)
      end
    end

    context 'when workflow execution fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: failed_execution_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => true
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/broadcast", {
          'success' => true
        })
      end

      it 'updates status to failed' do
        job.execute(workflow_run_id, job_options)

        expect_api_request(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}")
      end

      it 'broadcasts failure status' do
        job.execute(workflow_run_id, job_options)

        expect(WebMock).to have_requested(:post, %r{/broadcast}).at_least_once
      end
    end

    context 'when job encounters an exception' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        # Backend request returns failure response (simulating connection error caught by make_direct_backend_request)
        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: { 'success' => false, 'error' => 'Backend request failed: Connection failed' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => true
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/broadcast", {
          'success' => true
        })
      end

      it 'handles backend errors gracefully' do
        # Job handles errors gracefully without re-raising
        expect { job.execute(workflow_run_id, job_options) }.not_to raise_error
      end

      it 'updates status to failed on error' do
        job.execute(workflow_run_id, job_options)

        expect_api_request(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}")
      end

      it 'broadcasts error status' do
        job.execute(workflow_run_id, job_options)

        expect(WebMock).to have_requested(:post, %r{/broadcast}).at_least_once
      end

      it 'logs error details' do
        capture_logs_for(job)

        job.execute(workflow_run_id, job_options)

        expect_logged(:error, /Backend request failed|execution failed/)
      end
    end

    context 'when realtime broadcasting is disabled' do
      let(:options_without_realtime) { { 'realtime' => false } }

      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: successful_execution_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => true
        })
      end

      it 'does not broadcast status updates' do
        job.execute(workflow_run_id, options_without_realtime)

        expect(WebMock).not_to have_requested(:post, %r{/broadcast})
      end
    end

    context 'with runaway loop detection' do
      before do
        # Allow Redis operations to fail gracefully
        allow(Redis).to receive(:new).and_raise(StandardError.new('Redis unavailable'))

        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: successful_execution_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => true
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/broadcast", {
          'success' => true
        })
      end

      it 'continues execution when Redis is unavailable' do
        job.execute(workflow_run_id, job_options)

        expect_api_request(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}")
      end

      it 'aborts when recursion depth exceeds limit' do
        deep_options = job_options.merge('recursion_depth' => 15)

        job.execute(workflow_run_id, deep_options)

        expect(WebMock).not_to have_requested(:post, %r{/process})
      end
    end
  end

  describe '#fetch_workflow_run' do
    let(:job) { described_class.new }

    context 'when API call succeeds' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })
      end

      it 'returns workflow run data' do
        job.instance_variable_set(:@workflow_run_id, workflow_run_id)
        result = job.send(:fetch_workflow_run)

        expect(result).to eq(workflow_run_data)
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns nil' do
        job.instance_variable_set(:@workflow_run_id, workflow_run_id)
        result = job.send(:fetch_workflow_run)

        expect(result).to be_nil
      end

      it 'logs error' do
        job.instance_variable_set(:@workflow_run_id, workflow_run_id)
        capture_logs_for(job)

        job.send(:fetch_workflow_run)

        expect_logged(:error, /Failed to fetch/)
      end
    end
  end

  describe 'error handling scenarios' do
    let(:job) { described_class.new }

    context 'when status update fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: successful_execution_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => false,
          'error' => 'Update failed'
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/broadcast", {
          'success' => true
        })
      end

      it 'logs the update failure' do
        capture_logs_for(job)

        job.execute(workflow_run_id, job_options)

        expect_logged(:error, /Failed to update workflow run status/)
      end
    end

    context 'when broadcast fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflows/runs/lookup/#{workflow_run_id}", {
          'success' => true,
          'data' => { 'workflow_run' => workflow_run_data }
        })

        stub_request(:post, %r{/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/process})
          .to_return(
            status: 200,
            body: successful_execution_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}", {
          'success' => true
        })

        stub_backend_api_error(:post, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}/broadcast",
                               status: 500, error_message: 'Broadcast failed')
      end

      it 'continues execution despite broadcast failure' do
        # Should not raise an error
        job.execute(workflow_run_id, job_options)

        expect_api_request(:patch, "/api/v1/ai/workflows/#{workflow_id}/runs/#{workflow_run_id}")
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses ai_workflows queue' do
      expect(described_class.sidekiq_options['queue']).to eq('ai_workflows')
    end

    it 'has retry count of 3' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
