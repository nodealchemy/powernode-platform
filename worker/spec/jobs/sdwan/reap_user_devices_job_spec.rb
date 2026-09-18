# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-7046f6e448d6: BackendApiClient#handle_response
# returns the parsed JSON body verbatim (string keys) on 2xx; it is not a
# symbol-keyed {success:, data:} envelope. This job read the response with
# symbol keys, so `response[:success] == false` was always nil == false
# (never true) and a business-logic failure reported by the server was
# silently swallowed instead of raising.
RSpec.describe Sdwan::ReapUserDevicesJob, type: :job do
  let(:job_instance) { described_class.new }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute' do
    it 'raises when the string-keyed response body reports success => false' do
      mock_api_client_success(:post, { 'success' => false, 'error' => 'vault unreachable' })

      expect { job_instance.execute }
        .to raise_error(BackendApiClient::ApiError, /vault unreachable/)
    end

    it 'does not raise when the string-keyed response body reports success => true' do
      mock_api_client_success(:post, { 'success' => true, 'data' => { 'reaped_count' => 3 } })

      expect { job_instance.execute }.not_to raise_error
    end

    it 'propagates ApiError on a non-2xx response (the real BackendApiClient failure mode)' do
      # BackendApiClient#handle_response raises ApiError itself for any
      # non-2xx status; the `response['success'] == false` guard only ever
      # sees a 2xx body that carries a business-logic failure. Both paths
      # need covering — this is the one most reaps actually hit (vault down,
      # 500s), not the manual success:false envelope.
      mock_api_client_error(:post, BackendApiClient::ApiError.new('Backend server error', 500))

      expect { job_instance.execute }.to raise_error(BackendApiClient::ApiError, 'Backend server error')
    end
  end
end
