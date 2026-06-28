# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CampaignLand do
  let(:account) { create(:account) }
  let(:campaign) { create(:ai_campaign, account: account) }

  def land(attrs = {})
    Ai::CampaignLand.create!({
      campaign: campaign, account: account,
      source_branch: "campaign/#{campaign.id}", target_branch: "develop"
    }.merge(attrs))
  end

  describe "defaults + validation" do
    it "starts pending_approval" do
      expect(land.status).to eq("pending_approval")
    end

    it "rejects an unknown status" do
      l = land
      l.status = "bogus"
      expect(l).not_to be_valid
    end
  end

  describe "#on_approval_decision (unblock seam)" do
    it "approved → queued" do
      l = land
      l.on_approval_decision(double(status: "approved"))
      expect(l.reload.status).to eq("queued")
      expect(l.queued_at).to be_present
    end

    it "rejected → rejected" do
      l = land
      l.on_approval_decision(double(status: "rejected"))
      expect(l.reload.status).to eq("rejected")
    end

    it "expired → rejected" do
      l = land
      l.on_approval_decision(double(status: "expired"))
      expect(l.reload.status).to eq("rejected")
    end

    it "ignores decisions once past pending_approval" do
      l = land
      l.enqueue!
      l.on_approval_decision(double(status: "rejected"))
      expect(l.reload.status).to eq("queued")
    end
  end

  describe "state machine" do
    it "walks the happy path to landed" do
      l = land
      l.enqueue!
      l.begin_staging!
      l.mark_staged_ci!(staged_sha: "abc", pre_ci_pipeline_id: nil)
      l.begin_merging!
      l.begin_verifying!(merged_sha: "def", merge_operation_id: nil)
      l.land!
      expect(l.reload).to have_attributes(status: "landed", staged_sha: "abc", merged_sha: "def")
      expect(l.completed_at).to be_present
      expect(l).to be_terminal
    end

    it "park! records reason + files and is not terminal (re-queueable)" do
      l = land
      l.enqueue!
      l.begin_staging!
      l.park!(reason: "rebase_conflict", files: ["a.rb"])
      expect(l.reload).to have_attributes(status: "parked", parked_reason: "rebase_conflict", conflict_files: ["a.rb"])
      expect(l).not_to be_terminal
    end

    it "rolling_back → rolled_back is terminal" do
      l = land
      l.update!(status: "verifying")
      l.begin_rollback!
      expect(l).to be_active
      l.mark_rolled_back!
      expect(l.reload.status).to eq("rolled_back")
      expect(l).to be_terminal
    end
  end

  describe "scopes" do
    it "active_for returns only active lands for the target branch" do
      staging = land(status: "staging")
      land(status: "landed")           # terminal, excluded
      land(status: "queued")           # not active, excluded
      land(status: "staging", target_branch: "main") # other target

      result = Ai::CampaignLand.active_for("develop")
      expect(result).to contain_exactly(staging)
    end

    it "awaiting_approval / queued / parked select by status" do
      a = land
      q = land(status: "queued")
      p = land(status: "parked")
      expect(Ai::CampaignLand.awaiting_approval).to contain_exactly(a)
      expect(Ai::CampaignLand.queued).to contain_exactly(q)
      expect(Ai::CampaignLand.parked).to contain_exactly(p)
    end
  end
end
