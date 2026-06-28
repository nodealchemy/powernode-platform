# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CampaignProposal, type: :model do
  let(:account) { create(:account) }

  describe "validations" do
    it "is valid from the factory" do
      expect(build(:ai_campaign_proposal, account: account)).to be_valid
    end

    it "rejects an unknown status" do
      p = build(:ai_campaign_proposal, account: account, status: "bogus")
      expect(p).not_to be_valid
      expect(p.errors[:status]).to be_present
    end

    it "rejects an unknown workload" do
      expect(build(:ai_campaign_proposal, account: account, suggested_workload: "nope")).not_to be_valid
    end

    it "auto-derives a fingerprint before validation" do
      p = build(:ai_campaign_proposal, account: account, fingerprint: nil)
      p.valid?
      expect(p.fingerprint).to be_present
    end

    it "allows a blank suggested_driver but rejects an unknown one" do
      expect(build(:ai_campaign_proposal, account: account, suggested_driver: nil)).to be_valid
      expect(build(:ai_campaign_proposal, account: account, suggested_driver: "telepathy")).not_to be_valid
    end
  end

  describe ".fingerprint_for" do
    it "is stable across whitespace/case and varies by target" do
      a = described_class.fingerprint_for(scope: "repo-x", objective: "Fix  the  Bug", suggested_workload: "improvement-campaign")
      b = described_class.fingerprint_for(scope: "repo-x", objective: "fix the bug", suggested_workload: "improvement-campaign")
      c = described_class.fingerprint_for(scope: "repo-y", objective: "fix the bug", suggested_workload: "improvement-campaign")
      expect(a).to eq(b)
      expect(a).not_to eq(c)
    end
  end

  describe ".propose! dedupe (per-target, account-scoped)" do
    it "refreshes an open duplicate instead of creating a second row" do
      first = described_class.propose!(account: account, title: "T1", objective: "Same target", scope: "repo-x")
      second = described_class.propose!(account: account, title: "T1 refreshed", objective: "Same target",
                                        scope: "repo-x", evidence: { "n" => 2 })
      expect(second.id).to eq(first.id)
      expect(account.ai_campaign_proposals.count).to eq(1)
      expect(second.reload.title).to eq("T1 refreshed")
      expect(second.evidence).to eq("n" => 2)
    end

    it "does NOT resurrect a terminal (rejected) duplicate" do
      first = described_class.propose!(account: account, title: "T", objective: "Done target", scope: "repo-x")
      first.reject!(reason: "not now")
      again = described_class.propose!(account: account, title: "T again", objective: "Done target", scope: "repo-x")
      expect(again.id).to eq(first.id)
      expect(again.status).to eq("rejected")
      expect(account.ai_campaign_proposals.count).to eq(1)
    end

    it "scopes dedupe per account (same target, different accounts → distinct rows)" do
      other = create(:account)
      p1 = described_class.propose!(account: account, title: "T", objective: "Shared target", scope: "repo-x")
      p2 = described_class.propose!(account: other, title: "T", objective: "Shared target", scope: "repo-x")
      expect(p1.id).not_to eq(p2.id)
    end

    it "defaults workload to the campaign driver default" do
      p = described_class.propose!(account: account, title: "T", objective: "No workload given")
      expect(p.suggested_workload).to eq(Ai::DevLoop::CampaignDriver::DEFAULT_WORKLOAD)
    end

    it "converges (no 500) on a concurrent unique-index race (TOCTOU)" do
      existing = described_class.propose!(account: account, title: "First", objective: "Race target", scope: "repo-z")
      # Simulate the race: our initial find_by misses, then create! loses the unique-index
      # race to a concurrent insert. propose! must converge to the existing row, not 500.
      allow(account.ai_campaign_proposals).to receive(:find_by).and_return(nil)
      allow(account.ai_campaign_proposals).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

      result = described_class.propose!(account: account, title: "Second", objective: "Race target", scope: "repo-z")
      expect(result.id).to eq(existing.id)
    end
  end

  describe "review transitions" do
    let(:user) { create(:user, account: account) }

    it "queue! / approve! / reject! advance status + stamp reviewer" do
      p = create(:ai_campaign_proposal, account: account)
      p.queue!
      expect(p.status).to eq("queued")
      p.approve!(user)
      expect(p.status).to eq("approved")
      expect(p.reviewed_by).to eq(user)
      expect(p.reviewed_at).to be_present
      p.reject!(user, reason: "superseded")
      expect(p.status).to eq("rejected")
      expect(p.rejection_reason).to eq("superseded")
    end

    it "mark_spawned! back-links the campaign + goes terminal" do
      p = create(:ai_campaign_proposal, :approved, account: account)
      campaign = create(:ai_campaign, account: account)
      p.mark_spawned!(campaign)
      expect(p.status).to eq("spawned")
      expect(p.spawned_campaign).to eq(campaign)
      expect(p).to be_terminal
      expect(campaign.reload.source_proposal).to eq(p)
    end
  end

  describe "#to_campaign_args" do
    it "maps to Ai::DevLoop::CampaignDriver#start kwargs" do
      p = build(:ai_campaign_proposal, account: account, title: "Build X",
                objective: "Do the thing", suggested_workload: "feature-development",
                configuration: { "reuse_first" => true })
      args = p.to_campaign_args
      expect(args[:name]).to eq("Build X")
      expect(args[:description]).to eq("Do the thing")
      expect(args[:workload]).to eq("feature-development")
      expect(args[:configuration]).to eq("reuse_first" => true)
    end
  end
end
