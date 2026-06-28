# frozen_string_literal: true

require "rails_helper"

# Idempotency regression: the per-recipient sends are individually guarded, so the only thing that
# could raise was the post-loop batch_result report. When it raised, the whole job retried
# (retry: 5) and RE-SENT every email (up to 5×). The report is now record-and-swallow.
RSpec.describe Marketing::EmailBatchSendJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:campaign_id) { "camp-1" }
  let(:recipient_ids) { %w[r1 r2 r3] }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:with_api_retry) { |&blk| blk.call } # bypass backoff sleeps
    allow(api_client).to receive(:post).with("/api/v1/internal/notifications/send", anything).and_return({})
  end

  context "when the batch-result report fails after all sends completed" do
    before do
      allow(api_client).to receive(:post)
        .with("/api/v1/internal/marketing/batch_result", anything)
        .and_raise(StandardError, "report endpoint down")
    end

    it "does not raise (so Sidekiq does not retry and re-send the batch)" do
      expect { job.send(:execute, campaign_id, 1, recipient_ids) }.not_to raise_error
    end

    it "sends each recipient exactly once" do
      job.send(:execute, campaign_id, 1, recipient_ids)
      expect(api_client).to have_received(:post)
        .with("/api/v1/internal/notifications/send", anything).exactly(3).times
    end
  end

  context "happy path" do
    before do
      allow(api_client).to receive(:post).with("/api/v1/internal/marketing/batch_result", anything).and_return({})
    end

    it "sends each recipient once and reports the batch" do
      job.send(:execute, campaign_id, 2, recipient_ids)
      expect(api_client).to have_received(:post).with("/api/v1/internal/marketing/batch_result", anything).once
    end
  end
end
