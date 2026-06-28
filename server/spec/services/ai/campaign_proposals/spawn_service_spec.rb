# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CampaignProposals::SpawnService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:service) { described_class.new(account: account, user: user) }

  it "spawns an Ai::Campaign + dev-loop from the proposal and back-links it" do
    proposal = create(:ai_campaign_proposal, :approved, account: account, title: "Build X",
                      objective: "Do the thing", suggested_workload: "feature-development",
                      configuration: { "reuse_first" => true })

    campaign = service.spawn!(proposal)

    expect(campaign).to be_a(Ai::Campaign)
    expect(campaign.name).to eq("Build X")
    expect(campaign.configuration["workload"]).to eq("feature-development")
    expect(campaign.configuration["reuse_first"]).to be(true)
    expect(campaign.ralph_loops.first.branch).to start_with("campaign/")

    expect(proposal.reload.status).to eq("spawned")
    expect(proposal.spawned_campaign).to eq(campaign)
  end

  it "is idempotent — re-spawning returns the same campaign" do
    proposal = create(:ai_campaign_proposal, :approved, account: account)
    first = service.spawn!(proposal)
    second = service.spawn!(proposal.reload)
    expect(second.id).to eq(first.id)
    expect(account.ai_campaigns.count).to eq(1)
  end

  it "refuses a proposal from another account" do
    other = create(:ai_campaign_proposal, account: create(:account))
    expect { service.spawn!(other) }.to raise_error(ArgumentError)
  end
end
