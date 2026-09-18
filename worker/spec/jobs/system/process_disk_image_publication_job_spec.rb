# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-7046f6e448d6: BackendApiClient#handle_response
# returns the parsed JSON body verbatim (string keys) on 2xx; it is not a
# symbol-keyed {success:, data:} envelope. This job read the response with
# symbol keys, so `response[:success] == false` was always nil == false
# (never true) and a business-logic failure reported by the server was
# silently swallowed instead of raising.
RSpec.describe System::ProcessDiskImagePublicationJob, type: :job do
  let(:job_instance) { described_class.new }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute' do
    it 'raises when the string-keyed response body reports success => false' do
      mock_api_client_success(:post, { 'success' => false, 'error' => 'cosign verify failed' })

      expect { job_instance.execute('pub-1') }
        .to raise_error(/publication pub-1 processing failed: cosign verify failed/)
    end

    it 'does not raise when the string-keyed response body reports success => true' do
      mock_api_client_success(:post, { 'success' => true, 'data' => { 'publication_status' => 'published' } })

      expect { job_instance.execute('pub-1') }.not_to raise_error
    end

    it 'logs the string-keyed publication_status from the completion body' do
      mock_api_client_success(:post, { 'success' => true, 'data' => { 'publication_status' => 'published' } })

      allow(job_instance.send(:logger)).to receive(:info)
      expect(job_instance.send(:logger)).to receive(:info).with(/status=published/)

      job_instance.execute('pub-1')
    end
  end
end
