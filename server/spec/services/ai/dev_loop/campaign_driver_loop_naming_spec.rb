# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver, "campaign loop naming" do
  let(:account) { create(:account) }
  let(:driver) { described_class.new(account: account) }

  it "names a new campaign loop after the campaign (for the execution interface)" do
    result = driver.start(name: "Drain dev-improve backlog")
    expect(result[:loop].name).to eq("Drain dev-improve backlog")
    expect(result[:loop].description).to include("Drain dev-improve backlog")
  end

  it "relabel_campaign_loops! renames legacy campaign-<id> loops to the campaign name (idempotent)" do
    campaign = driver.start(name: "My Campaign")[:campaign]
    loop_record = campaign.ralph_loops.first
    loop_record.update_column(:name, "campaign-#{campaign.id}") # simulate a legacy-named loop

    expect(driver.relabel_campaign_loops!).to eq(1)
    expect(loop_record.reload.name).to eq("My Campaign")
    expect(driver.relabel_campaign_loops!).to eq(0) # idempotent — nothing left to rename
  end
end
