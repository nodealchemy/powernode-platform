# frozen_string_literal: true

require "rails_helper"

# Worker side of continual campaign discovery. The scan + dedupe happens server-side;
# this job only triggers the internal endpoint, so the backend client is mocked.
RSpec.describe AiCampaignDiscoveryJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
  end

  it "POSTs the scan endpoint and reports counts" do
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/campaign_discovery/scan")
      .and_return("data" => { "proposals_created" => 3, "accounts_processed" => 2 })

    expect(job.execute).to eq(proposals_created: 3, accounts_processed: 2)
  end

  it "skips gracefully when the backend is unavailable" do
    allow(api_client).to receive(:post).and_raise(Errno::ECONNREFUSED)
    expect(job.execute).to eq(skipped: true)
  end
end
