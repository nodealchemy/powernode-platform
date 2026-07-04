# frozen_string_literal: true

require "rails_helper"

# Worker side of the F5 scheduled evolution proposer. The scan + proposal
# writes happen server-side (Ai::SkillGraph::EvolutionProposalService); this
# job only triggers the endpoint, so the backend client is mocked. Mirrors
# ai_campaign_discovery_job_spec's style; with_api_retry's own retry/backoff
# semantics are already covered by base_job_spec.
RSpec.describe AiSkillEvolutionProposalJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
  end

  it "POSTs the evolution_proposals endpoint" do
    allow(api_client).to receive(:post)
      .with("/api/v1/ai/skill_graph/evolution_proposals")
      .and_return("data" => { "evolution_proposals" => 2, "conflict_review_proposals" => 1 })

    job.execute

    expect(api_client).to have_received(:post).with("/api/v1/ai/skill_graph/evolution_proposals")
  end

  it "retries a retryable backend error via with_api_retry then succeeds" do
    allow(job).to receive(:sleep)
    call_count = 0
    allow(api_client).to receive(:post) do
      call_count += 1
      raise BackendApiClient::ApiError.new("Server Error", 500) if call_count == 1

      { "data" => { "evolution_proposals" => 0, "conflict_review_proposals" => 0 } }
    end

    job.execute

    expect(call_count).to eq(2)
  end

  it "propagates a persistent backend failure so Sidekiq can reschedule the job" do
    allow(api_client).to receive(:post).and_raise(StandardError, "backend down")

    expect { job.execute }.to raise_error(StandardError, "backend down")
  end
end
