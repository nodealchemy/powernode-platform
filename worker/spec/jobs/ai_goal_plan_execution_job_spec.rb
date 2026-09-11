# frozen_string_literal: true

require 'rails_helper'

# goal_plans ruling, option A: the server now FAILS a step it has no dispatcher
# for, and answers 200 with status failed in the body. The job must log that
# and stop. Raising would put it through with_api_retry and then Sidekiq's
# retry: 2, re-driving a step that has already failed.
RSpec.describe AiGoalPlanExecutionJob, type: :job do
  let(:job) { described_class.new }
  let(:api) { instance_double('BackendApiClient') }
  let(:account_id) { 'account-303' }
  let(:path) { '/api/v1/internal/ai/goal_plans/execute_step' }

  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(job).to receive(:api_client).and_return(api)
    allow(job).to receive(:ai_suspended?).with(account_id).and_return(false)
    allow(job).to receive(:sleep) # with_api_retry's backoff
  end

  it 'logs a failed step and does not raise, so nothing retries it' do
    expect(api).to receive(:post).once.with(path, { step_id: 'step-1' })
      .and_return({ 'success' => true,
                    'data' => { 'step_id' => 'step-1', 'status' => 'failed',
                                'reason' => 'no dispatcher for step type agent_execution' } })
    expect(job).to receive(:log_info).with('Goal plan step executed', step_id: 'step-1', status: 'failed')
    allow(job).to receive(:log_info).with('Executing goal plan step', step_id: 'step-1')

    expect { job.execute('step-1', account_id) }.not_to raise_error
  end

  it 'still raises on a server error, so Sidekiq records the failure' do
    allow(api).to receive(:post).and_raise(BackendApiClient::ApiError.new('boom', 500))

    expect { job.execute('step-1', account_id) }.to raise_error(BackendApiClient::ApiError)
  end
end
