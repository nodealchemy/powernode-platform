# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Discovery::CampaignProposalService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  let(:repo1) { SecureRandom.uuid }
  let(:repo2) { SecureRandom.uuid }

  def rec(target_id:, type: "code_lint", **attrs)
    create(:ai_improvement_recommendation, account: account, status: "pending",
           target_type: "Devops::GitRepository", target_id: target_id, recommendation_type: type, **attrs)
  end

  def proposal_for(target_id)
    account.ai_campaign_proposals.where("evidence->>'target_id' = ?", target_id).first
  end

  it "returns no proposals when there is no pending backlog" do
    expect(service.scan!).to eq([])
  end

  it "aggregates the pending backlog per target into one improvement-campaign proposal" do
    rec(target_id: repo1, type: "code_lint")
    rec(target_id: repo1, type: "test_gap")
    rec(target_id: repo2, type: "dead_code")

    proposals = service.scan!
    expect(proposals.size).to eq(2) # one per distinct target

    p1 = proposal_for(repo1)
    expect(p1.source).to eq("improvement")
    expect(p1.suggested_workload).to eq("improvement-campaign")
    expect(p1.evidence["count"]).to eq(2)
    expect(p1.evidence["type_counts"]).to eq("code_lint" => 1, "test_gap" => 1)
    expect(p1.title).to include("2 improvement")
  end

  it "is idempotent across re-scans (refreshes the open proposal, no duplicate)" do
    rec(target_id: repo1)
    service.scan!
    rec(target_id: repo1) # backlog grew
    service.scan!

    proposals = account.ai_campaign_proposals.where("evidence->>'target_id' = ?", repo1)
    expect(proposals.count).to eq(1)
    expect(proposals.first.evidence["count"]).to eq(2) # refreshed
  end

  it "does not resurrect a proposal the operator rejected" do
    rec(target_id: repo1)
    p = service.scan!.first
    p.reject!(reason: "later")
    service.scan!

    expect(account.ai_campaign_proposals.where("evidence->>'target_id' = ?", repo1).count).to eq(1)
    expect(proposal_for(repo1).status).to eq("rejected")
  end

  it "ignores non-pending recommendations" do
    rec(target_id: repo1).update!(status: "applied")
    expect(service.scan!).to eq([])
  end
end
