# frozen_string_literal: true

require "rails_helper"

# IMP-842b56d3a5d4 — the cron half of the parked-step janitor.
#
# The server owns the sweep; this job is only the door onto it. That makes the
# ENDPOINT STRING the entire contract, and a mistyped one degrades to
# `BackendApiClient::ApiError` → `log_info("… Skipped: …")`: a permanently
# silent inert janitor, the exact failure mode SystemTaskReaperJob demonstrated
# for five weeks. Nothing else pins that string, so these examples do.
RSpec.describe AiProvisioningParkedStepReaperJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { {} }
  let(:api_client) { instance_spy(BackendApiClient) }
  let(:reap_path) { "/api/v1/internal/ai/provisioning/parked_steps/reap" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(api_client).to receive(:post)
      .and_return({ "success" => true, "data" => { "examined" => 0, "resumed" => 0 } })
  end

  it "POSTs the internal janitor-seam reap path" do
    job.execute({})

    expect(api_client).to have_received(:post).with(reap_path)
  end

  it "returns the sweep's counts" do
    allow(api_client).to receive(:post)
      .and_return({ "success" => true, "data" => { "examined" => 4, "resumed" => 3 } })

    expect(job.execute({})).to eq("examined" => 4, "resumed" => 3)
  end

  it "runs on the maintenance queue, matching its schedule entry" do
    expect(described_class.sidekiq_options["queue"]).to eq(:maintenance)
  end

  it "does not raise when the backend is unreachable — the next cron retries" do
    allow(api_client).to receive(:post).and_raise(Errno::ECONNREFUSED)

    expect { job.execute({}) }.not_to raise_error
  end

  it "reports zero counts when the API answers with an error envelope" do
    allow(api_client).to receive(:post).and_return({ "success" => false, "error" => "boom" })

    expect(job.execute({})).to eq("examined" => 0, "resumed" => 0)
  end
end
