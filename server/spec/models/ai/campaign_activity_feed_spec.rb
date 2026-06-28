# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Campaign, "#activity_feed" do
  let(:account) { create(:account) }
  let(:driver) { Ai::DevLoop::CampaignDriver.new(account: account) }
  let(:campaign) { driver.start(name: "obs")[:campaign] }

  it "returns a time-ordered (newest-first) feed of decisions, parked questions, and completed tasks" do
    campaign.record_decision!(decision_type: "build", title: "did a thing")
    campaign.park_question!(question: "which provider?")
    driver.record_increment!(campaign, title: "increment X", task_key: "x")

    feed = campaign.activity_feed(limit: 20)

    kinds = feed.map { |e| e[:kind] }
    expect(kinds).to include("decision", "parked_question", "task")
    ats = feed.map { |e| e[:at] }
    expect(ats).to eq(ats.compact.sort.reverse) # newest first, no nils
  end

  it "respects the limit" do
    5.times { |i| campaign.record_decision!(decision_type: "build", title: "d#{i}") }
    expect(campaign.activity_feed(limit: 3).size).to eq(3)
  end

  it "is included in CampaignDriver#status" do
    campaign.record_decision!(decision_type: "build", title: "x")
    status = driver.status(campaign)
    expect(status).to have_key(:activity)
    expect(status[:activity]).to be_an(Array)
  end
end
