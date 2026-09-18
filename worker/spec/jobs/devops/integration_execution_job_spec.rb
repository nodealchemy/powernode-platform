# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-7046f6e448d6: BackendApiClient#handle_response
# returns the parsed JSON body verbatim (string keys) on 2xx; it is not a
# symbol-keyed {success:, data:} envelope. This job read `response[:success]`
# / `response[:error]`, so a real success was always logged and counted as a
# failure (response[:success] was always nil, so the `else` branch always
# ran regardless of what the server actually reported).
RSpec.describe Devops::IntegrationExecutionJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:execution_id) { 'exec-123' }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:increment_counter)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute' do
    it 'logs and counts success when the string-keyed response body reports success => true' do
      allow(api_client).to receive(:post).and_return('success' => true)

      expect(job).to receive(:log_info).with('Integration execution completed', execution_id: execution_id)
      expect(job).to receive(:increment_counter).with('integration_execution_success')
      expect(job).not_to receive(:increment_counter).with('integration_execution_failure')

      job.execute('execution_id' => execution_id)
    end

    it 'logs and counts failure when the string-keyed response body reports success => false' do
      allow(api_client).to receive(:post).and_return('success' => false, 'error' => 'executor unavailable')

      expect(job).to receive(:log_error).with(
        'Integration execution failed', execution_id: execution_id, error: 'executor unavailable'
      )
      expect(job).to receive(:increment_counter).with('integration_execution_failure')

      job.execute('execution_id' => execution_id)
    end
  end
end
