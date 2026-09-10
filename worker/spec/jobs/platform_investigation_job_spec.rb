# frozen_string_literal: true

require "rails_helper"

# Worker side of the component status plane's investigation (increment A6).
# Ranking is an LLM call against a canonical agent, so it runs here and never
# in a request thread; the confidence rule, the agent and the skill gate all
# stay server-side, which is why this job only POSTs and reports.
RSpec.describe PlatformInvestigationJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }
  let(:investigation_id) { "019f7cb5-3858-7000-8000-000000000001" }
  let(:path) { "/api/v1/internal/platform/investigations/#{investigation_id}/conclude" }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
  end

  it "POSTs the conclude endpoint for the investigation it was given" do
    allow(api_client).to receive(:post).with(path, {}).and_return(
      "success" => true,
      "data" => { "investigation" => { "status" => "completed", "hypotheses" => [ {}, {} ] } }
    )

    job.execute("investigation_id" => investigation_id)

    expect(api_client).to have_received(:post).with(path, {})
  end

  it "accepts a symbol-keyed payload, as a direct enqueue produces" do
    allow(api_client).to receive(:post).and_return("success" => true, "data" => {})

    job.execute(investigation_id: investigation_id)

    expect(api_client).to have_received(:post).with(path, {})
  end

  it "refuses to run without an investigation id rather than POSTing a broken path" do
    allow(api_client).to receive(:post)

    expect { job.execute({}) }.to raise_error(ArgumentError, /investigation_id/)
    expect(api_client).not_to have_received(:post)
  end

  # THE POINT OF THE JOB. An investigation that never concludes stays open
  # forever, blocks the open-fingerprint rule for that component, and shows the
  # operator a spinner with no explanation. A quiet no-op here would be
  # indistinguishable from "still thinking", so the failure has to raise.
  it "raises when the backend answers without success, so Sidekiq retries" do
    allow(api_client).to receive(:post).and_return("success" => false, "error" => "not found")

    expect { job.execute("investigation_id" => investigation_id) }
      .to raise_error(StandardError, /did not conclude/)
  end

  it "raises on a non-Hash answer too" do
    allow(api_client).to receive(:post).and_return(nil)

    expect { job.execute("investigation_id" => investigation_id) }
      .to raise_error(StandardError, /did not conclude/)
  end

  it "retries a retryable backend error through with_api_retry, then succeeds" do
    allow(job).to receive(:sleep)
    calls = 0
    allow(api_client).to receive(:post) do
      calls += 1
      raise BackendApiClient::ApiError.new("Server Error", 500) if calls == 1

      { "success" => true, "data" => {} }
    end

    job.execute("investigation_id" => investigation_id)

    expect(calls).to eq(2)
  end

  it "propagates a persistent backend failure" do
    allow(api_client).to receive(:post).and_raise(StandardError, "backend down")

    expect { job.execute("investigation_id" => investigation_id) }
      .to raise_error(StandardError, "backend down")
  end

  it "runs on the AI orchestration queue and retries a bounded number of times" do
    expect(described_class.sidekiq_options["queue"]).to eq("ai_orchestration")
    expect(described_class.sidekiq_options["retry"]).to eq(2)
  end
end
