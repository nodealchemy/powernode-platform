# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowScheduleJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:schedule_id) { SecureRandom.uuid }
  let(:workflow_id) { SecureRandom.uuid }
  let(:workflow_run_id) { SecureRandom.uuid }

  let(:schedule_data) do
    {
      'id' => schedule_id,
      'name' => 'Test Schedule',
      'ai_workflow_id' => workflow_id,
      'status' => 'active',
      'is_active' => true,
      'cron_expression' => '0 10 * * *',
      'next_execution_at' => 1.minute.ago.iso8601,
      'execution_count' => 5,
      'input_variables' => { 'test' => 'value' },
      'configuration' => {
        'skip_if_running' => false,
        'max_consecutive_errors' => 10
      },
      'metadata' => { 'error_count' => 0 }
    }
  end

  let(:workflow_run_response) do
    {
      'success' => true,
      'data' => {
        'workflow_run' => {
          'run_id' => workflow_run_id,
          'status' => 'queued'
        }
      }
    }
  end

  describe '#execute' do
    let(:job) { described_class.new }

    context 'with successful schedule execution' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true,
          'data' => { 'schedule' => schedule_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/execute", workflow_run_response)

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-schedules/#{schedule_id}/calculate-next-execution", {
          'success' => true,
          'data' => { 'next_execution_at' => 1.day.from_now.iso8601 }
        })
      end

      it 'executes the scheduled workflow' do
        job.execute(schedule_id)

        expect_api_request(:post, "/api/v1/ai/workflows/#{workflow_id}/execute")
      end

      it 'updates schedule tracking' do
        job.execute(schedule_id)

        expect_api_request(:patch, "/api/v1/ai/workflow-schedules/#{schedule_id}")
      end

      it 'schedules next execution' do
        job.execute(schedule_id)

        expect_api_request(:post, "/api/v1/ai/workflow-schedules/#{schedule_id}/calculate-next-execution")
      end

      it 'logs successful execution' do
        capture_logs_for(job)

        job.execute(schedule_id)

        expect_logged(:info, /executed successfully/)
      end
    end

    context 'with schedule not ready' do
      context 'when inactive' do
        let(:inactive_schedule) { schedule_data.merge('is_active' => false) }

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => inactive_schedule }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end

      context 'when status is not active' do
        let(:paused_schedule) { schedule_data.merge('status' => 'paused') }

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => paused_schedule }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end

      context 'when next_execution_at is in the future' do
        let(:future_schedule) { schedule_data.merge('next_execution_at' => 1.hour.from_now.iso8601) }

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => future_schedule }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end

      context 'when before starts_at date' do
        let(:not_started_schedule) { schedule_data.merge('starts_at' => 1.hour.from_now.iso8601) }

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => not_started_schedule }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end

      context 'when after ends_at date' do
        let(:ended_schedule) { schedule_data.merge('ends_at' => 1.hour.ago.iso8601) }

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => ended_schedule }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end

      context 'when max_executions reached' do
        let(:maxed_schedule) { schedule_data.merge('max_executions' => 5, 'execution_count' => 5) }

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => maxed_schedule }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end

      context 'when workflow is running and skip_if_running is true' do
        let(:skip_running_schedule) do
          schedule_data.merge('configuration' => { 'skip_if_running' => true })
        end

        before do
          stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
            'success' => true,
            'data' => { 'schedule' => skip_running_schedule }
          })

          stub_backend_api_success(:get, "/api/v1/ai/workflows/#{workflow_id}/runs", {
            'success' => true,
            'data' => { 'runs' => [{ 'id' => 'run-1', 'status' => 'running' }] }
          })
        end

        it 'does not execute workflow' do
          job.execute(schedule_id)

          expect(WebMock).not_to have_requested(:post, %r{/execute})
        end
      end
    end

    context 'when schedule fetch fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns early' do
        result = job.execute(schedule_id)

        expect(result).to be_nil
      end
    end

    context 'when workflow execution fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true,
          'data' => { 'schedule' => schedule_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/execute", {
          'success' => false,
          'error' => 'Workflow execution failed'
        })

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-schedules/#{schedule_id}/calculate-next-execution", {
          'success' => true
        })
      end

      it 'handles failure and still schedules next execution' do
        job.execute(schedule_id)

        expect_api_request(:post, "/api/v1/ai/workflow-schedules/#{schedule_id}/calculate-next-execution")
      end

      it 'logs error message' do
        capture_logs_for(job)

        job.execute(schedule_id)

        expect_logged(:error, /execution failed/)
      end
    end

    context 'when job encounters exception' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true,
          'data' => { 'schedule' => schedule_data }
        })

        stub_backend_api_error(:post, "/api/v1/ai/workflows/#{workflow_id}/execute",
                               status: 500, error_message: 'Server error')

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true
        })
      end

      it 'handles error and raises for retry' do
        expect { job.execute(schedule_id) }.to raise_error(StandardError)
      end
    end

    context 'when max consecutive errors reached' do
      let(:error_schedule) do
        schedule_data.merge(
          'metadata' => { 'error_count' => 10 },
          'configuration' => { 'max_consecutive_errors' => 10, 'notifications' => { 'on_disable' => true } },
          'created_by' => 'user-123'
        )
      end

      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true,
          'data' => { 'schedule' => error_schedule }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflows/#{workflow_id}/execute", {
          'success' => false,
          'error' => 'Workflow failed'
        })

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-schedules/#{schedule_id}", {
          'success' => true
        })

        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'disables schedule' do
        job.execute(schedule_id)

        # Job makes 2 PATCH requests - verify the one that disables the schedule
        expect(WebMock).to have_requested(:patch, /workflow-schedules\/#{schedule_id}/)
          .with(body: hash_including({
            'schedule' => hash_including('status' => 'disabled')
          }))
      end

      it 'sends notification' do
        job.execute(schedule_id)

        expect_api_request(:post, '/api/v1/notifications')
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses ai_workflow_schedules queue' do
      expect(described_class.sidekiq_options['queue']).to eq('ai_workflow_schedules')
    end

    it 'has retry count of 3' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
