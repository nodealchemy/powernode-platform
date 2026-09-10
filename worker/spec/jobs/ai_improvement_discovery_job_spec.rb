# frozen_string_literal: true

require 'rails_helper'

# D1 — the clock half. The worker holds the schedule; the server owns the
# analyzers, the gates and the filing (it is the node with the working copy).
RSpec.describe AiImprovementDiscoveryJob, type: :job do
  let(:job_instance) { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  it 'POSTs the internal discovery endpoint and returns the summary' do
    expect(api_client_double).to receive(:post)
      .with('/api/v1/internal/ai/improvement_discovery/run', {})
      .and_return({ 'success' => true,
                    'data' => { 'accounts_processed' => 2, 'offers_created' => 3,
                                'offers_deduped' => 1, 'findings' => 4 } })

    result = job_instance.execute

    expect(result).to include('accounts_processed' => 2, 'offers_created' => 3)
  end

  it 'warns rather than staying silent when an analyzer ran degraded' do
    allow(api_client_double).to receive(:post).and_return(
      { 'success' => true,
        'data' => { 'accounts_processed' => 1, 'offers_created' => 0,
                    'analyzers_degraded' => [ { 'analyzer' => 'RuboCop', 'status' => 'no_gemfile' } ] } }
    )

    expect(job_instance).to receive(:log_warn)
      .with('Improvement discovery ran with degraded analyzers', hash_including(:degraded))

    job_instance.execute
  end

  it 'does NOT warn when every analyzer completed' do
    allow(api_client_double).to receive(:post).and_return(
      { 'success' => true, 'data' => { 'accounts_processed' => 1, 'offers_created' => 0,
                                       'analyzers_degraded' => [] } }
    )

    expect(job_instance).not_to receive(:log_warn)

    job_instance.execute
  end

  it 'raises so Sidekiq records the failure when the endpoint errors' do
    allow(api_client_double).to receive(:post).and_raise(StandardError, 'backend down')

    expect { job_instance.execute }.to raise_error(StandardError, 'backend down')
  end
end
