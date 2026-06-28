# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::CampaignTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  def exec(params)
    tool.execute(params: params.with_indifferent_access)
  end

  it "registers a campaign permission + declares its 5 actions" do
    expect(described_class::REQUIRED_PERMISSION).to eq("ai.campaigns.manage")
    expect(described_class.action_definitions.keys).to contain_exactly(
      "campaign_start", "campaign_status", "campaign_answer_question",
      "campaign_record_increment", "campaign_stop"
    )
  end

  it "campaign_record_increment records a passed task + decision and reflects completion" do
    id = exec(action: "campaign_start", name: "Obs")[:data][:campaign][:id]
    res = exec(action: "campaign_record_increment", campaign_id: id, title: "Increment 1", summary: "did it")
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:completion_pct]).to eq(100.0)
    expect(res[:data][:status]).to eq("passed")
  end

  it "campaign_record_increment requires a title" do
    id = exec(action: "campaign_start", name: "Obs")[:data][:campaign][:id]
    expect(exec(action: "campaign_record_increment", campaign_id: id)[:success]).to be false
  end

  it "campaign_start creates a campaign + a campaign-scoped loop" do
    res = exec(action: "campaign_start", name: "Audit billing", decision_authority: "trusted")
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:name]).to eq("Audit billing")
    expect(res[:data][:loop][:branch]).to start_with("campaign/")
  end

  it "campaign_start requires a name" do
    res = exec(action: "campaign_start")
    expect(res[:success]).to be false
  end

  it "campaign_status returns the ledger summary" do
    id = exec(action: "campaign_start", name: "X")[:data][:campaign][:id]
    res = exec(action: "campaign_status", campaign_id: id)
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:name]).to eq("X")
    expect(res[:data][:loops].size).to eq(1)
  end

  it "answers a parked question then stops the campaign" do
    id = exec(action: "campaign_start", name: "X")[:data][:campaign][:id]
    campaign = account.ai_campaigns.find(id)
    q = campaign.park_question!(question: "Pricing policy?")

    ans = exec(action: "campaign_answer_question", campaign_id: id, question_id: q.id, answer: "free 100/mo")
    expect(ans[:success]).to be true
    expect(q.reload.status).to eq("answered")

    stop = exec(action: "campaign_stop", campaign_id: id, summary: "done")
    expect(stop[:success]).to be true
    expect(campaign.reload.status).to eq("completed")
  end

  it "returns an error for an unknown campaign" do
    expect(exec(action: "campaign_status", campaign_id: "nope")[:success]).to be false
  end
end
