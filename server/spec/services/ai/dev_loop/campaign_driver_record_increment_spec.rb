# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver do
  let(:account) { create(:account) }
  let(:driver) { described_class.new(account: account) }
  let(:campaign) { driver.start(name: "obs")[:campaign] }

  describe "#record_increment! (auto-record progress per run)" do
    it "records a passed RalphTask + decision and reflects 100% completion" do
      driver.record_increment!(campaign, title: "Increment 1", summary: "did the thing", rationale: "because")

      campaign.reload
      expect(campaign.total_tasks).to eq(1)
      expect(campaign.completed_tasks).to eq(1)
      expect(campaign.completion_pct).to eq(100.0)

      loop_ = campaign.ralph_loops.first
      expect(loop_.ralph_tasks.where(status: "passed").count).to eq(1)
      expect(campaign.campaign_decisions.where(decision_type: "build").count).to eq(1)
    end

    it "is idempotent on task_key (re-recording does not double-count)" do
      driver.record_increment!(campaign, title: "Inc", task_key: "inc-1")
      driver.record_increment!(campaign, title: "Inc", task_key: "inc-1")
      expect(campaign.reload.total_tasks).to eq(1)
    end

    it "records a non-passed status (e.g. failed → failed_tasks, not completed)" do
      driver.record_increment!(campaign, title: "Broke", task_key: "x", status: "failed", decision_type: "defer")
      campaign.reload
      expect(campaign.failed_tasks).to eq(1)
      expect(campaign.completed_tasks).to eq(0)
    end

    it "raises if the campaign has no loop to record against" do
      bare = account.ai_campaigns.create!(name: "bare", status: "active", decision_authority: "trusted")
      expect { driver.record_increment!(bare, title: "x") }.to raise_error(ArgumentError, /no loop/)
    end
  end
end
