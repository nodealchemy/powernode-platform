# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-7046f6e448d6: BackendApiClient#handle_response
# returns the parsed JSON body verbatim (string keys) on 2xx; it is not a
# symbol-keyed {success:, data:} envelope. This job read the response with
# symbol keys, so `response[:success] == false` was always nil == false
# (never true) and a business-logic failure reported by the server was
# silently swallowed instead of raising.
RSpec.describe System::HostBridgeReaperJob, type: :job do
  let(:job_instance) { described_class.new }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute' do
    it 'raises when the string-keyed response body reports success => false' do
      mock_api_client_success(:post, { 'success' => false, 'error' => 'compiler unavailable' })

      expect { job_instance.execute }
        .to raise_error(BackendApiClient::ApiError, /compiler unavailable/)
    end

    it 'does not raise when the string-keyed response body reports success => true' do
      mock_api_client_success(:post, { 'success' => true, 'data' => { 'reaped_bridges' => 1 } })

      expect { job_instance.execute }.not_to raise_error
    end
  end
end
