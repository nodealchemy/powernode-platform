# frozen_string_literal: true

require "rails_helper"

# N+1 fix: the job used to GET /expired then DELETE one pool at a time (unbounded N+1). It now
# issues a single bulk purge_expired POST.
RSpec.describe AiMemoryPoolCleanupJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(api_client).to receive(:delete) # spied: asserted never called (N+1 removed)
    allow(api_client).to receive(:post).with("/api/v1/internal/ai/memory_pools/cleanup_results", anything).and_return({})
  end

  it "purges expired pools with a single bulk call (no per-pool DELETE)" do
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/memory_pools/purge_expired", anything)
      .and_return({ "data" => { "pools_cleaned" => 3, "bytes_freed" => 4_096 } })

    result = job.execute

    expect(result).to eq(pools_cleaned: 3, bytes_freed: 4_096)
    expect(api_client).to have_received(:post).with("/api/v1/internal/ai/memory_pools/purge_expired", anything).once
    expect(api_client).not_to have_received(:delete)
  end

  it "reports zeros when the purge fails (no raise)" do
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/memory_pools/purge_expired", anything)
      .and_raise(StandardError, "server down")

    expect { @result = job.execute }.not_to raise_error
    expect(@result).to eq(pools_cleaned: 0, bytes_freed: 0)
  end
end
