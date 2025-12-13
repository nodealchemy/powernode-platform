# frozen_string_literal: true

require 'rails_helper'

# Stub channel class for testing (defined in backend server)
class AiAgentExecutionChannel
  def self.broadcast_execution_complete(execution); end
  def self.broadcast_execution_error(execution, message, metadata = {}); end
end

RSpec.describe AiExecutionCancellationJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow_logging_methods
  end

  let(:execution_id) { SecureRandom.uuid }
  let(:account_id) { SecureRandom.uuid }
  let(:agent_id) { SecureRandom.uuid }
  let(:provider_id) { SecureRandom.uuid }

  let(:execution_data) do
    {
      'id' => execution_id,
      'account_id' => account_id,
      'ai_agent_id' => agent_id,
      'status' => 'running',
      'started_at' => 5.minutes.ago.iso8601,
      'result' => {},
      'metadata' => {
        'temp_files' => [],
        'connection_ids' => [],
        'related_job_ids' => []
      },
      'ai_agent' => {
        'id' => agent_id,
        'name' => 'Test Agent',
        'ai_provider' => {
          'id' => provider_id,
          'slug' => 'openai',
          'name' => 'OpenAI'
        }
      }
    }
  end

  describe '#execute' do
    let(:job) { described_class.new }

    context 'when execution is found and cancellable' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => execution_data }
        })
        stub_backend_api_success(:patch, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => execution_data.merge('status' => 'cancelled') }
        })
        stub_backend_api_success(:post, '/api/v1/ai/analytics/cancellations', {
          'success' => true
        })
        allow(AiAgentExecutionChannel).to receive(:broadcast_execution_complete)
      end

      it 'cancels the execution' do
        job.execute(execution_id)

        expect_api_request(:patch, "/api/v1/ai/agent_executions/#{execution_id}")
      end

      it 'broadcasts cancellation completion' do
        expect(AiAgentExecutionChannel).to receive(:broadcast_execution_complete)

        job.execute(execution_id)
      end

      it 'records cancellation metrics' do
        job.execute(execution_id)

        expect_api_request(:post, '/api/v1/ai/analytics/cancellations')
      end

      it 'logs success message' do
        capture_logs_for(job)

        job.execute(execution_id)

        expect_logged(:info, /Successfully cancelled/)
      end
    end

    context 'when execution is not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns early without error' do
        result = job.execute(execution_id)

        expect(result).to be_nil
      end
    end

    context 'when execution is already completed' do
      let(:completed_execution) do
        execution_data.merge('status' => 'completed')
      end

      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => completed_execution }
        })
      end

      it 'does not attempt to cancel' do
        job.execute(execution_id)

        expect(WebMock).not_to have_requested(:patch, %r{/ai/agent_executions/})
      end

      it 'logs warning message' do
        capture_logs_for(job)

        job.execute(execution_id)

        expect_logged(:warn, /cannot be cancelled/)
      end
    end

    context 'when execution is already cancelled' do
      let(:cancelled_execution) do
        execution_data.merge('status' => 'cancelled')
      end

      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => cancelled_execution }
        })
      end

      it 'does not attempt to cancel again' do
        job.execute(execution_id)

        expect(WebMock).not_to have_requested(:patch, %r{/ai/agent_executions/})
      end
    end

    context 'with different provider types' do
      context 'with Ollama provider' do
        let(:ollama_execution) do
          execution_data.merge(
            'ai_agent' => execution_data['ai_agent'].merge(
              'ai_provider' => { 'id' => provider_id, 'slug' => 'ollama', 'name' => 'Ollama' }
            ),
            'metadata' => { 'ollama_request_id' => 'req-123' }
          )
        end

        before do
          stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
            'success' => true,
            'data' => { 'execution' => ollama_execution }
          })
          stub_backend_api_success(:patch, "/api/v1/ai/agent_executions/#{execution_id}", {
            'success' => true,
            'data' => { 'execution' => ollama_execution.merge('status' => 'cancelled') }
          })
          stub_backend_api_success(:post, '/api/v1/ai/analytics/cancellations', { 'success' => true })
          allow(AiAgentExecutionChannel).to receive(:broadcast_execution_complete)
        end

        it 'handles Ollama-specific cancellation' do
          capture_logs_for(job)

          job.execute(execution_id)

          expect_logged(:info, /Ollama/)
        end
      end

      context 'with Anthropic provider' do
        let(:anthropic_execution) do
          execution_data.merge(
            'ai_agent' => execution_data['ai_agent'].merge(
              'ai_provider' => { 'id' => provider_id, 'slug' => 'anthropic', 'name' => 'Anthropic' }
            ),
            'metadata' => { 'anthropic_message_id' => 'msg-123' }
          )
        end

        before do
          stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
            'success' => true,
            'data' => { 'execution' => anthropic_execution }
          })
          stub_backend_api_success(:patch, "/api/v1/ai/agent_executions/#{execution_id}", {
            'success' => true,
            'data' => { 'execution' => anthropic_execution.merge('status' => 'cancelled') }
          })
          stub_backend_api_success(:post, '/api/v1/ai/analytics/cancellations', { 'success' => true })
          allow(AiAgentExecutionChannel).to receive(:broadcast_execution_complete)
        end

        it 'handles Anthropic-specific cancellation' do
          capture_logs_for(job)

          job.execute(execution_id)

          expect_logged(:info, /Anthropic/)
        end
      end
    end

    context 'with resource cleanup' do
      let(:execution_with_resources) do
        execution_data.merge(
          'metadata' => {
            'temp_files' => ['/tmp/test_file.txt'],
            'connection_ids' => ['conn-1', 'conn-2'],
            'related_job_ids' => ['job-1']
          }
        )
      end

      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => execution_with_resources }
        })
        stub_backend_api_success(:patch, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => execution_with_resources.merge('status' => 'cancelled') }
        })
        stub_backend_api_success(:post, '/api/v1/ai/analytics/cancellations', { 'success' => true })
        allow(AiAgentExecutionChannel).to receive(:broadcast_execution_complete)
      end

      it 'cleans up resources' do
        capture_logs_for(job)

        job.execute(execution_id)

        expect_logged(:info, /Cleaning up resources/)
      end
    end

    context 'when cancellation fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_executions/#{execution_id}", {
          'success' => true,
          'data' => { 'execution' => execution_data }
        })
        stub_backend_api_error(:patch, "/api/v1/ai/agent_executions/#{execution_id}",
                               status: 500, error_message: 'Server error')
        allow(AiAgentExecutionChannel).to receive(:broadcast_execution_error)
      end

      it 'handles cancellation error' do
        expect { job.execute(execution_id) }.to raise_error(StandardError)
      end

      it 'broadcasts error via channel' do
        expect(AiAgentExecutionChannel).to receive(:broadcast_execution_error)

        expect { job.execute(execution_id) }.to raise_error(StandardError)
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses ai_cancellations queue' do
      expect(described_class.sidekiq_options['queue']).to eq('ai_cancellations')
    end

    it 'has retry count of 1' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end
  end
end
