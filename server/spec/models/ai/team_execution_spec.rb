# frozen_string_literal: true

require "rails_helper"

# IMP-f301fd6563d2: the retry-idempotency claim (claim_retry! / mark_retry_queued! /
# mark_retry_unknown! / release_retry_claim!) is the guard that makes
# Api::V1::Ai::AgentTeamExecutionsController#retry_execution safe against a
# double-click / client retry queuing a second full agent-team execution.
# These specs exercise the model-level guarantee directly, in isolation from
# the controller and the worker HTTP boundary.
RSpec.describe Ai::TeamExecution do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, account: account) }
  let(:execution) { create(:ai_team_execution, :failed, account: account, agent_team: team) }

  describe "#claim_retry!" do
    it "wins for the first caller and returns true" do
      expect(execution.claim_retry!).to be true
      expect(execution.retry_state).to eq("enqueuing")
      expect(execution.retry_queued_at).to be_present
    end

    it "is atomic under a concurrent second claim: exactly one of two independently-loaded copies wins" do
      copy_a = described_class.find(execution.id)
      copy_b = described_class.find(execution.id)

      # copy_b's in-memory metadata is stale (loaded before copy_a's claim
      # committed) — this is exactly the shape a real concurrent second
      # request has, since it read the row before the first request's UPDATE
      # landed.
      expect(copy_a.claim_retry!).to be true
      expect(copy_b.metadata["retry_state"]).to be_nil

      expect(copy_b.claim_retry!).to be false

      # The loss reloads copy_b, so it now reflects the WINNER's claim
      # rather than a stale nil — this is what lets the controller answer a
      # losing request correctly instead of re-enqueuing.
      expect(copy_b.retry_state).to eq("enqueuing")
      expect(copy_b.retry_queued_at).to be_present
      expect(copy_b.retry_queued_at).to eq(copy_a.retry_queued_at)
    end

    it "does not win a second time for the same caller once claimed" do
      execution.claim_retry!
      expect(execution.claim_retry!).to be false
    end
  end

  describe "#mark_retry_queued!" do
    it "advances a won claim to queued and records the job id" do
      execution.claim_retry!
      execution.mark_retry_queued!(job_id: "sidekiq-jid-1")

      expect(execution.retry_state).to eq("queued")
      expect(execution.retry_job_id).to eq("sidekiq-jid-1")
      expect(execution.metadata["retry_job_id"]).to eq("sidekiq-jid-1")
    end

    it "tolerates a blank job id" do
      execution.claim_retry!
      execution.mark_retry_queued!

      expect(execution.retry_state).to eq("queued")
      expect(execution.metadata).not_to have_key("retry_job_id")
    end

    it "is a no-op (defence-in-depth) when retry_state isn't 'enqueuing'" do
      # No claim taken — retry_state is absent, not "enqueuing".
      execution.mark_retry_queued!(job_id: "should-not-land")

      expect(execution.reload.retry_state).to be_nil
      expect(execution.metadata).not_to have_key("retry_job_id")
    end
  end

  describe "#mark_retry_unknown!" do
    it "advances a won claim to unknown without touching retry_queued_at" do
      execution.claim_retry!
      queued_at = execution.retry_queued_at

      execution.mark_retry_unknown!

      expect(execution.retry_state).to eq("unknown")
      expect(execution.retry_queued_at).to eq(queued_at)
    end

    it "is a no-op (defence-in-depth) when retry_state isn't 'enqueuing'" do
      execution.mark_retry_unknown!

      expect(execution.reload.retry_state).to be_nil
    end
  end

  describe "#retry_enqueuing_stale?" do
    it "is false right after claiming" do
      execution.claim_retry!
      expect(execution.retry_enqueuing_stale?).to be false
    end

    it "is true once retry_queued_at is older than the worker timeout plus margin" do
      execution.claim_retry!
      stale_at = (described_class.retry_enqueuing_stale_after_seconds + 1).seconds.ago
      execution.update_column(:metadata, execution.metadata.merge("retry_queued_at" => stale_at.iso8601))

      expect(execution.reload.retry_enqueuing_stale?).to be true
    end

    it "is false once the state has moved past 'enqueuing'" do
      execution.claim_retry!
      execution.mark_retry_queued!
      expect(execution.retry_enqueuing_stale?).to be false
    end

    it "is false when no claim has been taken at all" do
      expect(execution.retry_enqueuing_stale?).to be false
    end
  end

  describe ".retry_enqueuing_stale_after_seconds" do
    it "derives from WorkerJobService's own request timeout, not a duplicated literal" do
      expect(described_class.retry_enqueuing_stale_after_seconds)
        .to eq(WorkerJobService.request_timeout_seconds + described_class::RETRY_STALE_MARGIN_SECONDS)
    end
  end

  describe "#release_retry_claim!" do
    it "clears retry_state and retry_queued_at so a later claim starts clean" do
      execution.claim_retry!
      execution.release_retry_claim!

      row = execution.reload
      expect(row.retry_state).to be_nil
      expect(row.retry_queued_at).to be_nil
      expect(row.claim_retry!).to be true
    end
  end
end
