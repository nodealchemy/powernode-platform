# frozen_string_literal: true

require "rails_helper"

# The tool-door (chat) decision rule in the proposal funnel, and the gateway request
# that must name the filing agent so the requester exclusion can fire.
RSpec.describe Ai::AgentProposals::Decision do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }
  let(:other_user) { create(:user, account: account) }
  let(:filer) { create(:ai_agent, account: account) }
  let(:other_agent) { create(:ai_agent, account: account) }
  let(:session) { McpSession.create!(user: owner, account: account) }
  let(:other_session) { McpSession.create!(user: owner, account: account) }
  let(:origin) { Ai::Tools::CallOrigin::MCP_OAUTH }
  let(:type) { "feature" }
  let(:deadline) { 2.hours.from_now }
  let!(:proposal) do
    account.ai_agent_proposals.create!(ai_agent_id: filer.id, target_user: owner, title: "Chat filed", proposal_type: type,
                                       priority: "medium", origin_mcp_session_id: session.id, review_deadline: deadline)
  end

  def decide(decision = "approved", by: owner, agent: filer, session_id: session.id, instruction: nil, from: origin)
    described_class.call(proposal, decision, by, origin: from, via_agent: agent, mcp_session_id: session_id,
                                                 instruction: instruction)
  end

  def refused(&block)
    expect(&block).to raise_error(described_class::Refused, /app/i)
    expect(proposal.reload.status).to eq("pending_review")
  end

  it "1. same session, live, owned by the decider, in the window: accepted (same_session)" do
    decide(instruction: "ship it please")

    expect(proposal.reload.status).to eq("approved")
    row = AuditLog.where(resource_id: proposal.id, action: "ai.proposal.approved").sole
    expect(row.user_id).to eq(owner.id)
    expect(row.metadata).to include("decided_via" => "chat", "chat_branch" => "same_session", "via_agent_id" => filer.id,
                                    "mcp_session_id" => session.id, "instruction" => "ship it please")
  end

  it "audits the instruction verbatim, capped at 500 characters" do
    decide(instruction: "x" * 800)
    expect(AuditLog.where(action: "ai.proposal.approved").sole.metadata["instruction"].length).to eq(500)
  end

  it "2. the same agent on another session is refused" do
    refused { decide(session_id: other_session.id) }
  end

  it "3. an expired or ended originating session is refused" do
    session.update!(status: "revoked")
    refused { decide }
  end

  it "3b. an idle originating session is refused" do
    session.update_columns(last_activity_at: 3.days.ago)
    refused { decide }
  end

  it "4. the same session with a different deciding user is refused" do
    refused { decide(by: other_user) }
  end

  it "5. past the review window is refused" do
    proposal.update_columns(review_deadline: 1.minute.ago)
    refused { decide }
  end

  context "other agent" do
    it "6. a different agent on another session, allowlisted type: accepted (other_agent)" do
      decide(agent: other_agent, session_id: other_session.id)

      expect(proposal.reload.status).to eq("approved")
      expect(AuditLog.where(action: "ai.proposal.approved").sole.metadata).to include("chat_branch" => "other_agent")
    end

    it "a different agent but on the originating session is judged as the same session (and refused if not owned)" do
      refused { decide(agent: other_agent, by: other_user) }
    end

    it "rejections follow the same rule" do
      refused { decide("rejected", session_id: other_session.id) }
      decide("rejected", agent: other_agent, session_id: other_session.id)
      expect(proposal.reload.status).to eq("rejected")
    end

    it "a tool-door call with no resolvable agent is refused (fail closed)" do
      refused { decide(agent: nil, session_id: other_session.id) }
      refused { decide(agent: nil) }
    end

    it "an origin outside the declared vocabulary is not an admitted door" do
      expect { decide(from: "made_up") }.to raise_error(ArgumentError, /unknown decision origin/)
    end

    it "the decider must be a user of the proposal's account" do
      stranger = create(:user, account: create(:account))
      refused { decide(agent: other_agent, session_id: other_session.id, by: stranger) }
    end
  end

  context "a type outside CHAT_DECIDABLE_TYPES" do
    let(:type) { "agent_create" }

    it "7. is refused with the app card pointer and the gateway request stays pending" do
      allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true)
      request = Ai::Approvals::Gateway.new(account: account).request!(approvable: proposal, kind: "agent_proposal").approval_request

      refused { decide(agent: other_agent, session_id: other_session.id) }
      expect(request.reload.status).to eq("pending")
    end
  end

  it "the allowlist is feature, code_change, process_improvement, architecture, knowledge_update" do
    expect(Ai::AgentProposal::CHAT_DECIDABLE_TYPES).to match_array(%w[feature code_change process_improvement architecture knowledge_update])
  end

  it "9. with proposals.chat_decisions_enabled off every tool-door decision is refused" do
    SiteSetting.create!(key: "proposals.chat_decisions_enabled", value: "false", setting_type: "boolean")
    refused { decide }
    refused { decide(agent: other_agent, session_id: other_session.id) }
  end

  it "is on by default (no setting row)" do
    expect(SiteSetting.get("proposals.chat_decisions_enabled")).to be_nil
    decide
    expect(proposal.reload.status).to eq("approved")
  end

  it "10. a REST own-session decision is unchanged, even by the filing agent's user" do
    described_class.call(proposal, "approved", owner, origin: Ai::ApprovalDecision::REST_SESSION)
    expect(proposal.reload.status).to eq("approved")
    expect(AuditLog.where(action: "ai.proposal.approved").sole.metadata).not_to include("decided_via")
  end

  context "an accepted chat decision with a gateway request" do
    it "settles the pending ApprovalRequest outright" do
      allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true)
      request = Ai::Approvals::Gateway.new(account: account).request!(approvable: proposal, kind: "agent_proposal").approval_request

      decide(agent: other_agent, session_id: other_session.id)
      expect(request.reload.status).to eq("approved")
      expect(proposal.reload.handoff_kind).to eq("dev_task")
    end
  end

  describe "the gateway request names the filing agent" do
    it "carries agent_id so the filing agent can never decide its own request" do
      allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true)
      allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true)
      allow_any_instance_of(Ai::AgentOutreachService).to receive(:notify_proposal).and_return(true)
      account.update!(settings: { "ai" => { "approvals_via_gateway" => true } })

      filed = Ai::ProposalService.new(account: account).create(
        agent: filer, target_user: owner, params: { title: "Via gateway", proposal_type: "feature", priority: "low" }
      )
      request = Ai::ApprovalRequest.for_source("Ai::AgentProposal", filed.id).sole

      expect(request.request_data["agent_id"]).to eq(filer.id)
      expect(request.requester_excluded?(approver: other_user, origin: origin, agent: filer)).to be true
      expect(request.requester_excluded?(approver: other_user, origin: origin, agent: other_agent)).to be false
    end
  end
end
