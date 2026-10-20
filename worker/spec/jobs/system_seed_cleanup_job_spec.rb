# frozen_string_literal: true

require "rails_helper"

# IMP-02a42b90598b (D13): the seed cleanup sweep is its own short job, posted
# WITHOUT retry (a retried long request would overlap itself).
RSpec.describe SystemSeedCleanupJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:endpoint) { "/api/v1/system/worker_api/seed_cleanup/sweep" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:acquire_lock).and_return(true)
    allow(job).to receive(:release_lock)
  end

  it "POSTs the sweep endpoint once, with no retry and a short timeout" do
    allow(api_client).to receive(:post_no_retry).and_return({ "data" => { "swept" => 3 } })

    expect(job.execute).to include(swept: 3)
    expect(api_client).to have_received(:post_no_retry).with(endpoint, {}, timeout: described_class::REQUEST_TIMEOUT_SEC)
    expect(described_class::REQUEST_TIMEOUT_SEC).to be <= 60
  end

  it "returns ok: false on an API error instead of raising" do
    allow(api_client).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new("down"))
    expect(job.execute).to include(ok: false)
  end

  it "skips when the previous run still holds the lock" do
    allow(job).to receive(:acquire_lock).and_return(false)
    expect(api_client).not_to receive(:post_no_retry)
    expect(job.execute).to include(skipped: true)
  end
end
