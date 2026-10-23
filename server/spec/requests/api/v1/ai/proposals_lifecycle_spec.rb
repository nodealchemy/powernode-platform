# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Proposals lifecycle", type: :request do
  let(:account) { create(:account) }
  let(:reviewer) { user_with_permissions("ai.proposals.view", "ai.proposals.review", account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:headers) { auth_headers_for(reviewer).merge("Content-Type" => "application/json") }

  def file(type, **attrs)
    account.ai_agent_proposals.create!({ ai_agent_id: agent.id, target_user: reviewer, title: "P #{type}",
                                         proposal_type: type, priority: "medium" }.merge(attrs))
  end

  def data
    JSON.parse(response.body)["data"]
  end

  it "approve returns the dev_task handoff" do
    proposal = file("feature")
    post "/api/v1/ai/proposals/#{proposal.id}/approve", headers: headers

    expect(response).to have_http_status(:ok)
    expect(data["status"]).to eq("approved")
    expect(data["handoff"]).to include("kind" => "dev_task", "id" => proposal.reload.handoff_id, "acknowledged_only" => false)
    expect(data["reviewed_by"]["id"]).to eq(reviewer.id)
  end

  it "labels an acknowledgement-only approval as such" do
    proposal = file("knowledge_update")
    post "/api/v1/ai/proposals/#{proposal.id}/approve", headers: headers

    expect(data["handoff"]).to include("kind" => "acknowledged", "acknowledged_only" => true)
    expect(data["handoff"]["label"]).to match(/acknowledg/i)
  end

  it "shows the implemented reference" do
    proposal = file("feature")
    proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
    proposal.implement!(ref: "cafe1234")
    get "/api/v1/ai/proposals/#{proposal.id}", headers: headers

    expect(data).to include("status" => "implemented", "implemented_ref" => "cafe1234")
    expect(data["implemented_at"]).to be_present
  end

  it "refuses to approve an expired proposal (422) and hands nothing off" do
    proposal = file("feature", review_deadline: 1.hour.ago)
    Ai::ProposalService.new(account: account).expire_overdue!

    post "/api/v1/ai/proposals/#{proposal.id}/approve", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(proposal.reload.status).to eq("expired")
    expect(Ai::RalphTask.count).to eq(0)
  end

  it "filters by the expired status" do
    expired = file("feature", review_deadline: 1.hour.ago)
    Ai::ProposalService.new(account: account).expire_overdue!
    file("feature")

    get "/api/v1/ai/proposals", params: { status: "expired" }, headers: headers
    expect(data["proposals"].map { |p| p["id"] }).to eq([ expired.id ])
  end

  it "withdraw is audited with the acting user" do
    proposal = file("feature")
    put "/api/v1/ai/proposals/#{proposal.id}/withdraw", headers: headers

    expect(proposal.reload.status).to eq("withdrawn")
    expect(AuditLog.where(resource_id: proposal.id, action: "ai.proposal.withdrawn").sole.user_id).to eq(reviewer.id)
  end

  it "refuses a batch approve per id for a proposal that hands work off, and approves an acknowledgement" do
    feature = file("feature")
    knowledge = file("knowledge_update")
    post "/api/v1/ai/proposals/batch_review", params: { proposal_ids: [ feature.id, knowledge.id ], decision: "approve" }.to_json,
                                              headers: headers

    expect(response).to have_http_status(:ok)
    by_id = data["results"].index_by { |r| r["id"] }
    expect(by_id[feature.id]).to include("code" => 422, "error" => Ai::ProposalService::APPROVE_ONE_AT_A_TIME)
    expect(by_id[knowledge.id]).to include("status" => "approved", "handoff_kind" => "acknowledged", "acknowledged_only" => true)
    expect(feature.reload.status).to eq("pending_review")
  end

  it "still batch-rejects" do
    feature = file("feature")
    post "/api/v1/ai/proposals/batch_review", params: { proposal_ids: [ feature.id ], decision: "reject" }.to_json, headers: headers

    expect(data["results"].first).to include("id" => feature.id, "status" => "rejected")
  end

  it "shows an agent_create card's tier and families" do
    proposal = file("agent_create", proposed_changes: { "slug" => "s", "tool_access" => { "tool_families" => %w[knowledge] },
                                                       "model_config" => { "model_requirements" => { "tier" => "light" } } })
    get "/api/v1/ai/proposals/#{proposal.id}", headers: headers

    expect(data["agent_spec"]).to include("tier" => "light", "tool_families" => %w[knowledge], "tools" => [], "unknown" => [])
  end

  it "reports a failed single approval as 422 and leaves it pending" do
    bad = file("agent_create", proposed_changes: { "name" => "no slug" })
    post "/api/v1/ai/proposals/#{bad.id}/approve", headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(bad.reload.status).to eq("pending_review")
  end
end
