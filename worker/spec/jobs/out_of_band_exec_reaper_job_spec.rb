# frozen_string_literal: true

require "rails_helper"

# IMP-9ce0ed39c557 — the worker-side half of the out-of-band-exec reaper.
# Mirrors System::IdentityReaperJob's own shape exactly: posts to a
# worker_api endpoint, all real work happens server-side.
RSpec.describe OutOfBandExecReaperJob do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  # OutOfBandExecReaperJob calls BackendApiClient.new.post directly, mirroring
  # System::IdentityReaperJob's own code exactly — NOT the memoized #api_client
  # helper SystemTaskReaperJob uses, so this stubs .new rather than the helper.
  let(:api_client) { instance_spy(BackendApiClient) }

  let(:reap_path) { "/api/v1/system/worker_api/out_of_band_exec/reap" }

  before do
    allow(BackendApiClient).to receive(:new).and_return(api_client)
    allow(api_client).to receive(:post).and_return(
      { "data" => { "ok" => true, "failed_count" => 0, "ran_at" => Time.current.iso8601 } }
    )
  end

  it "posts to the out-of-band-exec reap endpoint with no body" do
    job.execute

    expect(api_client).to have_received(:post).with(reap_path, {})
  end

  it "returns the server's response" do
    allow(api_client).to receive(:post).and_return(
      { "data" => { "ok" => true, "failed_count" => 3, "ran_at" => "2026-09-28T00:00:00Z" } }
    )

    result = job.execute

    expect(result.dig("data", "failed_count")).to eq(3)
  end

  it "raises when the server reports failure, so Sidekiq retries" do
    allow(api_client).to receive(:post).and_return({ success: false, error: "db down" })

    expect { job.execute }.to raise_error(BackendApiClient::ApiError, /db down/)
  end

  it "raises when the endpoint itself errors" do
    allow(api_client).to receive(:post).and_raise(BackendApiClient::ApiError.new("upstream down"))

    expect { job.execute }.to raise_error(BackendApiClient::ApiError)
  end

  describe "sidekiq_options" do
    it "retries a failed sweep rather than silently dropping it" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end

    it "runs on the system queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("system")
    end
  end
end
