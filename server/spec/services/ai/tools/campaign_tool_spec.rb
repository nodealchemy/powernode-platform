# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::CampaignTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  def exec(params)
    tool.execute(params: params.with_indifferent_access)
  end

  it "registers a campaign permission + declares its actions" do
    expect(described_class::REQUIRED_PERMISSION).to eq("ai.campaigns.manage")
    expect(described_class.action_definitions.keys).to contain_exactly(
      "campaign_propose", "campaign_approve_proposal",
      "campaign_start", "campaign_status", "campaign_claim", "campaign_release",
      "campaign_answer_question", "campaign_record_increment", "campaign_check_rebase", "campaign_stop"
    )
  end

  it "campaign_propose enqueues a deduped proposal" do
    res = exec(action: "campaign_propose", title: "Add export", objective: "Add CSV export to reports", scope: "core")
    expect(res[:success]).to be true
    expect(res[:data][:proposal][:status]).to eq("proposed")

    # Same target again → refreshed, not duplicated.
    exec(action: "campaign_propose", title: "Add export v2", objective: "Add CSV export to reports", scope: "core")
    expect(account.ai_campaign_proposals.count).to eq(1)
  end

  it "campaign_approve_proposal approves + spawns the campaign in one step (concierge path)" do
    pid = exec(action: "campaign_propose", title: "Build widget", objective: "Build the widget",
               suggested_workload: "feature-development")[:data][:proposal][:id]

    res = exec(action: "campaign_approve_proposal", proposal_id: pid)
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:name]).to eq("Build widget")
    expect(res[:data][:loop][:branch]).to start_with("campaign/")

    proposal = account.ai_campaign_proposals.find(pid)
    expect(proposal.status).to eq("spawned")
    expect(proposal.spawned_campaign_id).to eq(res[:data][:campaign][:id])
  end

  it "campaign_approve_proposal errors on an unknown proposal" do
    expect(exec(action: "campaign_approve_proposal", proposal_id: "nope")[:success]).to be false
  end

  it "campaign_check_rebase advises behind campaigns and returns the advised set" do
    res = exec(action: "campaign_check_rebase", target_branch: "develop")
    expect(res[:success]).to be true
    expect(res[:data][:target_branch]).to eq("develop")
    expect(res[:data]).to have_key(:advised)
  end

  it "campaign_claim takes the single-driver lease and campaign_release frees it" do
    id = exec(action: "campaign_start", name: "X")[:data][:campaign][:id]

    claimed = exec(action: "campaign_claim", campaign_id: id, holder: "sess-a")
    expect(claimed[:success]).to be true
    expect(claimed[:data][:ok]).to be true
    expect(claimed[:data][:lease][:holder]).to eq("sess-a")

    blocked = exec(action: "campaign_claim", campaign_id: id, holder: "sess-b")
    expect(blocked[:data][:ok]).to be false
    expect(blocked[:data][:held_by]).to eq("sess-a")

    released = exec(action: "campaign_release", campaign_id: id, holder: "sess-a")
    expect(released[:data][:ok]).to be true
    expect(exec(action: "campaign_claim", campaign_id: id, holder: "sess-b")[:data][:ok]).to be true
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
