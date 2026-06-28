# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Land::LandingQueue do
  let(:account) { create(:account) }
  let(:campaign) { create(:ai_campaign, account: account) }

  def land(status:, queued_at: Time.current, priority: 0, target: "develop")
    Ai::CampaignLand.create!(
      campaign: campaign, account: account, status: status,
      source_branch: "campaign/#{campaign.id}", target_branch: target,
      queued_at: queued_at, priority: priority
    )
  end

  describe ".next_for" do
    it "picks the oldest queued land and transitions it to staging" do
      newer = land(status: "queued", queued_at: 1.minute.ago)
      older = land(status: "queued", queued_at: 10.minutes.ago)

      picked = described_class.next_for(target_branch: "develop", account: account)

      expect(picked).to eq(older)
      expect(picked.reload.status).to eq("staging")
      expect(newer.reload.status).to eq("queued")
    end

    it "honors priority over age" do
      land(status: "queued", queued_at: 10.minutes.ago, priority: 0)
      high = land(status: "queued", queued_at: 1.minute.ago, priority: 5)

      expect(described_class.next_for(target_branch: "develop", account: account)).to eq(high)
    end

    it "returns nil when a land is already active for the target (serialization)" do
      land(status: "staging") # active, holds the slot
      land(status: "queued")

      expect(described_class.next_for(target_branch: "develop", account: account)).to be_nil
    end

    it "returns nil when the queue is empty" do
      expect(described_class.next_for(target_branch: "develop", account: account)).to be_nil
    end

    it "isolates targets — an active land on one target does not block another" do
      land(status: "staging", target: "develop")
      q = land(status: "queued", target: "main")

      expect(described_class.next_for(target_branch: "main", account: account)).to eq(q)
    end
  end
end
