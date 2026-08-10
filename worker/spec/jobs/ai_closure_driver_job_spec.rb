# frozen_string_literal: true

require "rails_helper"

# Worker side of the OODA closure driver (IMP-e041c835a40d). All activation
# gates live server-side; this job only enumerates eligible accounts and
# ticks each one, so the backend client is mocked.
RSpec.describe AiClosureDriverJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_warn)
  end

  it "no-ops on an empty accounts list (driver disabled server-side)" do
    allow(api_client).to receive(:get)
      .with("/api/v1/internal/ai/closure_driver/accounts")
      .and_return("data" => [])

    # No :post stub exists, so any tick attempt would raise — the eq proves
    # the job returned without driving anything.
    expect(job.execute).to eq(accounts_processed: 0, cycles_run: 0)
  end

  it "ticks each eligible account and sums cycles" do
    allow(api_client).to receive(:get)
      .with("/api/v1/internal/ai/closure_driver/accounts")
      .and_return("data" => %w[acc-1 acc-2])
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/closure_driver/run", { account_id: "acc-1" })
      .and_return("data" => { "cycles_run" => 2 })
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/closure_driver/run", { account_id: "acc-2" })
      .and_return("data" => { "cycles_run" => 1 })

    expect(job.execute).to eq(accounts_processed: 2, cycles_run: 3)
  end

  it "isolates a failing account tick (others still run)" do
    allow(api_client).to receive(:get)
      .with("/api/v1/internal/ai/closure_driver/accounts")
      .and_return("data" => %w[acc-bad acc-good])
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/closure_driver/run", { account_id: "acc-bad" })
      .and_raise(Errno::ECONNRESET)
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/closure_driver/run", { account_id: "acc-good" })
      .and_return("data" => { "cycles_run" => 1 })

    expect(job.execute).to eq(accounts_processed: 1, cycles_run: 1)
  end
end
