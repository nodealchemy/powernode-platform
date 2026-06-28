# frozen_string_literal: true

require "rails_helper"

# Worker side of the auto-land pipeline. All git/state work happens server-side;
# these jobs only sequence internal-API phase calls, so the backend client is mocked.
RSpec.describe "campaign auto-land worker jobs", type: :job do
  let(:api_client) { instance_double(BackendApiClient) }

  def install_client(job)
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
  end

  describe AiCampaignLandSchedulerJob do
    let(:job) { described_class.new }
    before { install_client(job) }

    it "dispatches a land job per picked land" do
      allow(api_client).to receive(:post)
        .with("/api/v1/internal/ai/campaign_lands/process_queue")
        .and_return("data" => { "lands" => [{ "id" => "L1" }, { "id" => "L2" }] })

      expect(AiCampaignLandJob).to receive(:perform_async).with("land_id" => "L1")
      expect(AiCampaignLandJob).to receive(:perform_async).with("land_id" => "L2")

      expect(job.execute[:dispatched]).to eq(2)
    end
  end

  describe AiCampaignLandJob do
    let(:job) { described_class.new }
    before { install_client(job) }

    it "stages then polls staged CI when staged_ci" do
      allow(api_client).to receive(:post)
        .with("/api/v1/internal/ai/campaign_lands/L1/stage")
        .and_return("data" => { "land" => { "status" => "staged_ci" } })

      expect(AiCampaignLandCiPollJob).to receive(:perform_async)
        .with("land_id" => "L1", "gate" => "staged", "attempt" => 0)

      job.execute("land_id" => "L1")
    end

    it "stops (no poll) when staging parks" do
      allow(api_client).to receive(:post).and_return("data" => { "land" => { "status" => "parked" } })
      expect(AiCampaignLandCiPollJob).not_to receive(:perform_async)
      job.execute("land_id" => "L1")
    end
  end

  describe AiCampaignLandCiPollJob do
    let(:job) { described_class.new }
    before { install_client(job) }

    it "merges and polls the target gate on staged success" do
      allow(api_client).to receive(:get).and_return("data" => { "ci_status" => "success" })
      expect(api_client).to receive(:post).with("/api/v1/internal/ai/campaign_lands/L1/merge")
      expect(described_class).to receive(:perform_async).with("land_id" => "L1", "gate" => "target", "attempt" => 0)

      job.execute("land_id" => "L1", "gate" => "staged", "attempt" => 0)
    end

    it "parks on staged CI failure" do
      allow(api_client).to receive(:get).and_return("data" => { "ci_status" => "failure" })
      expect(api_client).to receive(:post).with("/api/v1/internal/ai/campaign_lands/L1/park", { reason: "staged CI failed" })

      job.execute("land_id" => "L1", "gate" => "staged", "attempt" => 0)
    end

    it "verifies on target success (server lands)" do
      allow(api_client).to receive(:get).and_return("data" => { "ci_status" => "success" })
      expect(api_client).to receive(:post).with("/api/v1/internal/ai/campaign_lands/L1/verify")

      job.execute("land_id" => "L1", "gate" => "target", "attempt" => 0)
    end

    it "re-enqueues with backoff while CI is pending" do
      allow(api_client).to receive(:get).and_return("data" => { "ci_status" => "pending" })
      expect(described_class).to receive(:perform_in)
        .with(described_class::POLL_INTERVAL_SECONDS, hash_including("attempt" => 1))

      job.execute("land_id" => "L1", "gate" => "staged", "attempt" => 0)
    end

    it "parks after the attempt ceiling" do
      allow(api_client).to receive(:get).and_return("data" => { "ci_status" => "pending" })
      expect(api_client).to receive(:post).with(%r{/park\z}, hash_including(:reason))

      job.execute("land_id" => "L1", "gate" => "staged", "attempt" => described_class::MAX_ATTEMPTS - 1)
    end
  end
end
