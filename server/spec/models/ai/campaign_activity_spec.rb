# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Campaign, "last_activity_at heartbeat" do
  let(:account) { create(:account) }
  let(:campaign) { account.ai_campaigns.create!(name: "c", status: "active", decision_authority: "trusted") }

  it "is set on start!" do
    c = account.ai_campaigns.create!(name: "s", status: "created", decision_authority: "trusted")
    expect { c.start! }.to change { c.reload.last_activity_at }.from(nil)
  end

  it "advances on record_decision! (real work)" do
    campaign.update_column(:last_activity_at, 1.hour.ago)
    expect { campaign.record_decision!(decision_type: "build", title: "x") }
      .to(change { campaign.reload.last_activity_at })
  end

  it "advances on park_question! (real work)" do
    campaign.update_column(:last_activity_at, 1.hour.ago)
    expect { campaign.park_question!(question: "q?") }
      .to(change { campaign.reload.last_activity_at })
  end

  it "does NOT advance on a plain snapshot/status read" do
    t = 1.hour.ago.change(usec: 0)
    campaign.update_column(:last_activity_at, t)
    campaign.snapshot_progress!
    expect(campaign.reload.last_activity_at).to be_within(1.second).of(t)
  end

  it "exposes last_activity_at in #summary" do
    campaign.record_decision!(decision_type: "build", title: "x")
    expect(campaign.summary).to have_key(:last_activity_at)
  end
end
