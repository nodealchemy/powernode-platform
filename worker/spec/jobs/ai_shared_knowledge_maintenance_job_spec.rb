# frozen_string_literal: true

require "rails_helper"

# Backlog-drain fix: the server caps each shared_maintenance call (import /
# quality recalc / embedding backfill each process a bounded batch and report
# `remaining`). A single daily pass can never drain a multi-thousand backlog
# (~5.8k stale entries observed live), so the job now chains rate-limited
# follow-up passes until the backlog reports drained, hard-capped by MAX_PASSES.
RSpec.describe AiSharedKnowledgeMaintenanceJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  let(:audit_response) do
    { "data" => { "stats" => { "total_entries" => 10, "avg_quality_score" => 0.8 } } }
  end

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(api_client).to receive(:get)
      .with("/api/v1/ai/memory/shared_knowledge", params: { per_page: 1 })
      .and_return(audit_response)
  end

  def maintenance_response(import_remaining: 0, recalc_remaining: 0, backfill_remaining: 0)
    {
      "success" => true,
      "data" => {
        "import_result" => { "success" => true, "imported" => 1, "skipped" => 0, "remaining" => import_remaining },
        "quality_recalc" => { "success" => true, "recalculated" => 2, "remaining" => recalc_remaining },
        "embedding_backfill" => { "success" => true, "embedded" => 3, "failed" => 0, "remaining" => backfill_remaining },
        "stats" => { "total" => 10 }
      }
    }
  end

  describe "#execute" do
    it "runs a single pass and does not chain when the backlog is drained" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return(maintenance_response)

      job.execute

      expect(api_client).to have_received(:post).with("/api/v1/ai/memory/shared_maintenance").once
      expect(described_class.jobs).to be_empty
    end

    it "chains a rate-limited follow-up pass when any step reports remaining backlog" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return(maintenance_response(recalc_remaining: 5_400))

      job.execute

      expect(described_class.jobs.size).to eq(1)
      chained = described_class.jobs.first
      expect(chained["args"]).to eq([2])
      # perform_in schedules with an `at` timestamp ~CHAIN_DELAY_SECONDS out
      expect(chained["at"]).to be_within(5).of(Time.now.to_f + described_class::CHAIN_DELAY_SECONDS)
    end

    it "sums remaining across import, recalc, and backfill when deciding to chain" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return(maintenance_response(import_remaining: 1))

      job.execute

      expect(described_class.jobs.size).to eq(1)
    end

    it "increments the pass counter on each chained invocation" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return(maintenance_response(backfill_remaining: 200))

      job.execute(3)

      expect(described_class.jobs.first["args"]).to eq([4])
    end

    it "stops chaining at MAX_PASSES even with backlog remaining" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return(maintenance_response(recalc_remaining: 999))

      job.execute(described_class::MAX_PASSES)

      expect(described_class.jobs).to be_empty
    end

    it "does not chain when the response has no data payload" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return({ "success" => true })

      job.execute

      expect(described_class.jobs).to be_empty
    end

    it "treats the quality audit as non-critical (no raise on audit failure)" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_return(maintenance_response)
      allow(api_client).to receive(:get)
        .with("/api/v1/ai/memory/shared_knowledge", params: { per_page: 1 })
        .and_raise(StandardError, "audit endpoint down")

      expect { job.execute }.not_to raise_error
    end

    it "propagates maintenance endpoint failures so Sidekiq retries" do
      allow(api_client).to receive(:post)
        .with("/api/v1/ai/memory/shared_maintenance")
        .and_raise(BackendApiClient::ApiError.new("boom", 502))

      expect { job.execute }.to raise_error(BackendApiClient::ApiError)
      expect(described_class.jobs).to be_empty
    end
  end
end
