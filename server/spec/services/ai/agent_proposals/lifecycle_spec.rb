# frozen_string_literal: true

require "rails_helper"

# The agent-proposal lifecycle (improvement 01a16822-1ceb): approval is a
# TRIAGE that hands the work off, every transition writes one AuditLog row, a
# lapse is "expired" (never "withdrawn"), and a proposal is "implemented" only
# when something proves it.
RSpec.describe "Ai::AgentProposal lifecycle" do
  include PermissionTestHelpers

  let(:account) { create(:account) }
  let(:reviewer) { create(:user, account: account) }
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  def file_proposal(type: "feature", changes: {}, **attrs)
    account.ai_agent_proposals.create!(
      { ai_agent_id: agent.id, target_user: reviewer, title: "Proposal #{type}", description: "Do the #{type} thing",
        rationale: "because", proposal_type: type, priority: "high", proposed_changes: changes }.merge(attrs)
    )
  end

  def audit_actions_for(proposal)
    AuditLog.where(resource_type: "Ai::AgentProposal", resource_id: proposal.id).order(:created_at, :id).pluck(:action)
  end

  def audit_rows(proposal, action)
    AuditLog.where(resource_type: "Ai::AgentProposal", resource_id: proposal.id, action: action)
  end

  describe "vocabulary" do
    it "has an expired status distinct from withdrawn" do
      expect(Ai::AgentProposal::STATUSES).to include("expired", "withdrawn")
    end

    it "registers the seven audit actions" do
      %w[approved rejected withdrawn expired implemented handed_off handoff_abandoned].each do |verb|
        expect(AuditActions.all_actions).to include("ai.proposal.#{verb}")
      end
    end
  end

  describe "handoff on approve, by proposal_type" do
    %w[feature code_change process_improvement].each do |type|
      it "#{type}: creates one dev-improve task carrying metadata.proposal_id" do
        proposal = file_proposal(type: type)

        expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.to change(Ai::RalphTask, :count).by(1)

        task = Ai::RalphTask.find(proposal.reload.handoff_id)
        expect(proposal.handoff_kind).to eq("dev_task")
        expect(proposal.status).to eq("approved")
        expect(task.ralph_loop.name).to eq("dev-improve")
        expect(task.ralph_loop.account_id).to eq(account.id)
        expect(task.status).to eq("pending")
        expect(task.metadata["proposal_id"]).to eq(proposal.id)
        expect(task.task_key).to match(/\AIMP-\h{12}\z/)
        expect(task.description).to include(proposal.title)
      end
    end

    %w[architecture sweep_execution].each do |type|
      it "#{type}: opens one campaign proposal carrying metadata.proposal_id" do
        proposal = file_proposal(type: type)

        expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.to change(Ai::CampaignProposal, :count).by(1)

        campaign_proposal = Ai::CampaignProposal.find(proposal.reload.handoff_id)
        expect(proposal.handoff_kind).to eq("campaign_proposal")
        expect(proposal.status).to eq("approved")
        expect(campaign_proposal.status).to eq("proposed")
        expect(campaign_proposal.evidence["proposal_id"]).to eq(proposal.id)
        expect(campaign_proposal.title).to eq(proposal.title)
      end
    end

    it "agent_create: creates an ACCOUNT-scoped, inactive agent from the payload, implemented at once, ref = agent id" do
      spec = { "slug" => "release-scribe", "name" => "Release Scribe", "agent_type" => "assistant",
               "description" => "Writes release notes", "system_prompt" => "You write release notes.",
               "tool_access" => { "tool_families" => %w[search_knowledge knowledge] },
               "model_config" => { "model_requirements" => { "tier" => "standard" } } }
      proposal = file_proposal(type: "agent_create", changes: spec)

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }
        .to change { Ai::Agent.where(slug: "release-scribe").count }.by(1)

      expect(Ai::Agent.where(slug: "release-scribe", account_id: nil)).to be_empty
      created = Ai::Agent.find_by!(slug: "release-scribe")
      expect(created.account_id).to eq(account.id)
      expect(created.is_system).to be false
      expect(created.source_key).to eq("release-scribe")
      expect(created.creator).to eq(reviewer)
      expect(created.status).to eq("inactive")
      expect(created.system_prompt).to eq("You write release notes.")
      expect(created.mcp_metadata.dig("tool_access", "tool_families")).to eq(%w[knowledge])
      expect(created.mcp_metadata.dig("tool_access", "tools")).to eq(%w[search_knowledge])
      proposal.reload
      expect(proposal.status).to eq("implemented")
      expect(proposal.handoff_kind).to eq("agent")
      expect(proposal.handoff_id).to eq(created.id)
      expect(proposal.implemented_ref).to eq(created.id)
      expect(proposal.implemented_at).to be_present
    end

    it "agent_create: a payload mixing a family and an action name stores each under its own key" do
      proposal = file_proposal(type: "agent_create",
                               changes: { "slug" => "mixer", "name" => "Mixer", "agent_type" => "assistant",
                                          "tool_access" => { "tool_families" => %w[knowledge search_knowledge knowledge] } })

      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      access = Ai::Agent.find(proposal.reload.handoff_id).mcp_metadata["tool_access"]
      expect(access["tool_families"]).to eq(%w[knowledge])
      expect(access["tools"]).to eq(%w[search_knowledge])
    end

    it "agent_create: an unknown tool family fails the handoff, rolls the approval back and creates nothing" do
      proposal = file_proposal(type: "agent_create",
                               changes: { "slug" => "rogue", "name" => "Rogue", "agent_type" => "assistant",
                                          "tool_access" => { "tool_families" => %w[knowledge totally_made_up] } })

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }
        .to raise_error(Ai::AgentProposals::Handoff::Failed, /totally_made_up/)
      expect(Ai::Agent.where(slug: "rogue")).to be_empty
      expect(proposal.reload.status).to eq("pending_review")
      expect(audit_actions_for(proposal)).to be_empty
    end

    it "agent_create: an existing agent with that slug is reused within the account, never overwritten" do
      existing = create(:ai_agent, account: account, name: "Release Scribe", slug: "release-scribe")
      existing.update!(system_prompt: "OPERATOR EDITED")
      proposal = file_proposal(type: "agent_create",
                               changes: { "slug" => "release-scribe", "name" => "Release Scribe",
                                          "agent_type" => "assistant", "system_prompt" => "from payload" })

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::Agent, :count)
      expect(existing.reload.system_prompt).to eq("OPERATOR EDITED")
      expect(proposal.reload.implemented_ref).to eq(existing.id)
    end

    it "agent_create: a same-slug GLOBAL canonical is not reused; the account gets its own agent" do
      global = create(:ai_agent, :global, is_system: true, name: "Release Scribe", slug: "release-scribe")
      proposal = file_proposal(type: "agent_create",
                               changes: { "slug" => "release-scribe", "name" => "Release Scribe", "agent_type" => "assistant" })

      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      expect(proposal.reload.handoff_id).not_to eq(global.id)
      expect(Ai::Agent.find(proposal.handoff_id).account_id).to eq(account.id)
    end

    it "agent_create: a payload that cannot make an agent refuses the approval and leaves the proposal pending" do
      proposal = file_proposal(type: "agent_create", changes: { "name" => "No slug" })

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }
        .to raise_error(Ai::AgentProposals::Handoff::Failed)
      proposal.reload
      expect(proposal.status).to eq("pending_review")
      expect(proposal.handoff_kind).to be_nil
      expect(audit_actions_for(proposal)).to be_empty
    end

    it "configuration with a gitops source: handed to GitOps (which applies and marks it implemented)" do
      proposal = file_proposal(type: "configuration", changes: { "source" => "gitops", "diff" => { "kind" => "template" } })

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::RalphTask, :count)
      expect(proposal.reload.handoff_kind).to eq("gitops")
      expect(proposal.status).to eq("approved")
    end

    it "configuration filed by a tool (no apply service): an explicit acknowledgement" do
      proposal = file_proposal(type: "configuration", changes: { "action" => "update", "data_source_id" => SecureRandom.uuid })

      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      expect(proposal.reload.handoff_kind).to eq("acknowledged")
      expect(proposal.handoff_id).to be_nil
      expect(proposal.status).to eq("approved")
    end

    it "knowledge_update: an explicit acknowledgement" do
      proposal = file_proposal(type: "knowledge_update")

      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      expect(proposal.reload.handoff_kind).to eq("acknowledged")
    end
  end

  describe "idempotency" do
    it "a duplicate approve (cascade replay) creates no second task and no second approved row" do
      proposal = file_proposal(type: "feature")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      first_id = proposal.reload.handoff_id

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::RalphTask, :count)
      expect { Ai::AgentProposal.find(proposal.id).approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::RalphTask, :count)
      expect(proposal.reload.handoff_id).to eq(first_id)
      expect(audit_rows(proposal, "ai.proposal.approved").count).to eq(1)
      expect(audit_rows(proposal, "ai.proposal.handed_off").count).to eq(1)
    end

    it "the task key is derived from the proposal, so a lost handoff pointer cannot mint a second task" do
      proposal = file_proposal(type: "code_change")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      proposal.update_columns(handoff_kind: nil, handoff_id: nil)

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::RalphTask, :count)
      expect(proposal.reload.handoff_kind).to eq("dev_task")
    end

    it "a duplicate campaign handoff opens one campaign proposal" do
      proposal = file_proposal(type: "architecture")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      proposal.update_columns(handoff_kind: nil, handoff_id: nil)

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::CampaignProposal, :count)
    end

    it "the gateway cascade replayed after approval creates no second task" do
      proposal = file_proposal(type: "feature")
      request = instance_double(Ai::ApprovalRequest, status: "approved", decisions: double(order: double(last: double(approver: reviewer, origin: Ai::ApprovalDecision::REST_SESSION))))

      proposal.on_approval_decision(request)
      expect { Ai::AgentProposal.find(proposal.id).on_approval_decision(request) }.not_to change(Ai::RalphTask, :count)
      expect(Ai::RalphTask.where("metadata ->> 'proposal_id' = ?", proposal.id).count).to eq(1)
    end
  end

  describe "no handoff for a proposal that was not approved" do
    it "reject! hands nothing off" do
      proposal = file_proposal(type: "feature")

      expect { proposal.reject!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.not_to change(Ai::RalphTask, :count)
      expect(proposal.reload.handoff_kind).to be_nil
      expect(proposal.status).to eq("rejected")
    end

    it "an expired proposal cannot be approved afterwards, and hands nothing off" do
      proposal = file_proposal(type: "feature", review_deadline: 1.hour.ago)
      Ai::ProposalService.new(account: account).expire_overdue!

      expect { proposal.reload.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.to raise_error(Ai::AgentProposal::InvalidTransition)
      expect(Ai::RalphTask.count).to eq(0)
      expect(proposal.reload.status).to eq("expired")
      expect(proposal.handoff_kind).to be_nil
    end

    it "a rejected proposal cannot be approved afterwards" do
      proposal = file_proposal(type: "feature")
      proposal.reject!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.to raise_error(Ai::AgentProposal::InvalidTransition)
      expect(Ai::RalphTask.count).to eq(0)
    end

    it "the gateway cascade for a rejected or expired request hands nothing off" do
      %w[rejected expired].each do |status|
        proposal = file_proposal(type: "feature")
        request = instance_double(Ai::ApprovalRequest, status: status, decisions: double(order: double(last: double(approver: reviewer, origin: Ai::ApprovalDecision::REST_SESSION))))

        proposal.on_approval_decision(request)
        expect(proposal.reload.handoff_kind).to be_nil
      end
      expect(Ai::RalphTask.count).to eq(0)
    end
  end

  describe "the gateway door" do
    it "an approved request hands off exactly like the controller door" do
      proposal = file_proposal(type: "process_improvement")
      request = instance_double(Ai::ApprovalRequest, status: "approved", decisions: double(order: double(last: double(approver: reviewer, origin: Ai::ApprovalDecision::REST_SESSION))))

      expect(proposal.on_approval_decision(request)).to eq(Ai::ApprovalRequest::DISPATCH_EXECUTED)
      expect(proposal.reload.handoff_kind).to eq("dev_task")
      expect(proposal.reviewed_by).to eq(reviewer)
    end

    it "an expired request makes the proposal expired (a lapse), not rejected" do
      proposal = file_proposal(type: "feature")
      request = instance_double(Ai::ApprovalRequest, status: "expired", decisions: double(order: double(last: double(approver: reviewer, origin: Ai::ApprovalDecision::REST_SESSION))))

      proposal.on_approval_decision(request)
      expect(proposal.reload.status).to eq("expired")
      expect(proposal.reviewed_at).to be_nil
    end
  end

  describe "batch_review" do
    let(:service) { Ai::ProposalService.new(account: account) }
    let(:rest) { Ai::ApprovalDecision::REST_SESSION }

    it "approves an acknowledgement-only proposal in a batch and labels it" do
      knowledge = file_proposal(type: "knowledge_update")

      results = service.batch_review(proposal_ids: [ knowledge.id ], action: "approve", reviewer: reviewer, origin: rest)

      expect(results.first).to include(id: knowledge.id, status: "approved", handoff_kind: "acknowledged", acknowledged_only: true)
    end

    it "refuses a batch approve, per id, for every proposal that hands work off" do
      feature = file_proposal(type: "feature")
      arch = file_proposal(type: "architecture")
      agent_create = file_proposal(type: "agent_create", changes: { "slug" => "x" })
      gitops = file_proposal(type: "configuration", changes: { "source" => "gitops" })
      knowledge = file_proposal(type: "knowledge_update")
      plain_config = file_proposal(type: "configuration", changes: { "action" => "update" })

      results = service.batch_review(proposal_ids: [ feature, arch, agent_create, gitops, knowledge, plain_config ].map(&:id),
                                     action: "approve", reviewer: reviewer, origin: rest)

      refused = results.select { |r| r[:code] == 422 }
      expect(refused.map { |r| r[:id] }).to match_array([ feature, arch, agent_create, gitops ].map(&:id))
      expect(refused.map { |r| r[:error] }.uniq).to eq([ Ai::ProposalService::APPROVE_ONE_AT_A_TIME ])
      expect([ feature, arch, agent_create, gitops ].map { |p| p.reload.status }.uniq).to eq(%w[pending_review])
      expect(Ai::RalphTask.count).to eq(0)
      expect([ knowledge, plain_config ].map { |p| p.reload.handoff_kind }).to eq(%w[acknowledged acknowledged])
    end

    it "keeps reject batchable, whatever the type" do
      feature = file_proposal(type: "feature")
      arch = file_proposal(type: "architecture")

      results = service.batch_review(proposal_ids: [ feature.id, arch.id ], action: "reject", reviewer: reviewer, origin: rest)

      expect(results.map { |r| r[:status] }).to all(eq("rejected"))
      expect(Ai::RalphTask.count + Ai::CampaignProposal.count).to eq(0)
    end

    it "does not decide anything without a person's own session" do
      knowledge = file_proposal(type: "knowledge_update")
      expect { service.batch_review(proposal_ids: [ knowledge.id ], action: "approve", reviewer: reviewer, origin: nil) }
        .to raise_error(ArgumentError, /origin/)
    end
  end

  describe "expiry" do
    it "marks an overdue pending proposal expired, with reviewed_at nil, and leaves withdrawn to withdraw!" do
      overdue = file_proposal(type: "feature", review_deadline: 2.hours.ago)
      fresh = file_proposal(type: "feature", review_deadline: 2.hours.from_now)
      withdrawn = file_proposal(type: "feature")
      withdrawn.withdraw!

      count = Ai::ProposalService.new(account: account).expire_overdue!

      expect(count).to eq(1)
      expect(overdue.reload.status).to eq("expired")
      expect(overdue.reviewed_at).to be_nil
      expect(fresh.reload.status).to eq("pending_review")
      expect(withdrawn.reload.status).to eq("withdrawn")
      expect(withdrawn.reviewed_at).to be_nil
    end
  end

  describe "implementation" do
    it "implement! requires a reference" do
      proposal = file_proposal(type: "feature")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      expect { proposal.implement!(ref: "") }.to raise_error(ArgumentError, /ref/)
      expect { proposal.implement!(ref: nil) }.to raise_error(ArgumentError, /ref/)
      expect(proposal.reload.status).to eq("approved")
    end

    it "implement! records implemented_at and implemented_ref" do
      proposal = file_proposal(type: "feature")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      proposal.implement!(ref: "abc123")
      proposal.reload
      expect(proposal.status).to eq("implemented")
      expect(proposal.implemented_ref).to eq("abc123")
      expect(proposal.implemented_at).to be_within(5.seconds).of(Time.current)
    end

    it "implement! refuses a proposal that was never approved" do
      proposal = file_proposal(type: "feature")
      expect { proposal.implement!(ref: "abc123") }.to raise_error(Ai::AgentProposal::InvalidTransition)
    end

    it "a campaign handed off by an architecture proposal marks it implemented when the campaign completes" do
      proposal = file_proposal(type: "architecture")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      campaign_proposal = Ai::CampaignProposal.find(proposal.reload.handoff_id)
      campaign = create(:ai_campaign, account: account)
      campaign_proposal.update!(status: "spawned", spawned_campaign: campaign)

      campaign.complete!("all increments landed")

      proposal.reload
      expect(proposal.status).to eq("implemented")
      expect(proposal.implemented_ref).to eq("campaign:#{campaign.id}")
    end

    it "completing a campaign unrelated to any agent proposal changes nothing" do
      campaign = create(:ai_campaign, account: account)
      expect { campaign.complete!("done") }.not_to raise_error
    end
  end

  describe "audit" do
    it "writes one row per transition with the reviewer as actor and the handoff in the details" do
      proposal = file_proposal(type: "feature")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      expect(audit_actions_for(proposal)).to eq(%w[ai.proposal.approved ai.proposal.handed_off])
      approved = audit_rows(proposal, "ai.proposal.approved").sole
      expect(approved.user_id).to eq(reviewer.id)
      expect(approved.account_id).to eq(account.id)
      expect(approved.metadata).to include("handoff_kind" => "dev_task", "handoff_id" => proposal.reload.handoff_id,
                                           "proposal_type" => "feature")
      handed = audit_rows(proposal, "ai.proposal.handed_off").sole
      expect(handed.metadata).to include("handoff_kind" => "dev_task", "handoff_id" => proposal.handoff_id)
    end

    it "an acknowledged approval audits the acknowledgement" do
      proposal = file_proposal(type: "knowledge_update")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      expect(audit_rows(proposal, "ai.proposal.handed_off").sole.metadata).to include("handoff_kind" => "acknowledged")
    end

    it "rejected, withdrawn, expired and implemented each write one row" do
      rejected = file_proposal(type: "feature")
      rejected.reject!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      expect(audit_actions_for(rejected)).to eq(%w[ai.proposal.rejected])
      expect(audit_rows(rejected, "ai.proposal.rejected").sole.user_id).to eq(reviewer.id)

      withdrawn = file_proposal(type: "feature")
      withdrawn.withdraw!
      expect(audit_actions_for(withdrawn)).to eq(%w[ai.proposal.withdrawn])

      expired = file_proposal(type: "feature", review_deadline: 1.hour.ago)
      Ai::ProposalService.new(account: account).expire_overdue!
      expect(audit_actions_for(expired)).to eq(%w[ai.proposal.expired])
      row = audit_rows(expired, "ai.proposal.expired").sole
      expect(row.user_id).to be_nil
      expect(row.source).to eq("system")

      done = file_proposal(type: "feature")
      done.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      done.implement!(ref: "deadbeef")
      expect(audit_actions_for(done)).to eq(%w[ai.proposal.approved ai.proposal.handed_off ai.proposal.implemented])
      expect(audit_rows(done, "ai.proposal.implemented").sole.metadata).to include("implemented_ref" => "deadbeef")
    end

    it "an agent_create approval audits approved, handed_off and implemented with the agent id" do
      proposal = file_proposal(type: "agent_create",
                               changes: { "slug" => "audit-scribe", "name" => "Audit Scribe", "agent_type" => "assistant",
                                          "system_prompt" => "You audit." })
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)

      expect(audit_actions_for(proposal)).to eq(%w[ai.proposal.approved ai.proposal.handed_off ai.proposal.implemented])
      expect(audit_rows(proposal, "ai.proposal.implemented").sole.metadata).to include("implemented_ref" => proposal.reload.implemented_ref)
    end

    it "a refused transition writes no audit row" do
      proposal = file_proposal(type: "feature")
      proposal.reject!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION) }.to raise_error(Ai::AgentProposal::InvalidTransition)
      expect(audit_actions_for(proposal)).to eq(%w[ai.proposal.rejected])
    end
  end

  describe "a decision needs an origin" do
    it "approve!(nil) with no origin raises and changes nothing" do
      proposal = file_proposal(type: "feature")

      expect { proposal.approve!(nil, origin: nil) }.to raise_error(ArgumentError, /origin/)
      expect { proposal.approve!(nil, origin: "") }.to raise_error(ArgumentError, /origin/)
      expect { proposal.reject!(nil, origin: nil) }.to raise_error(ArgumentError, /origin/)
      expect(proposal.reload.status).to eq("pending_review")
      expect(Ai::RalphTask.count).to eq(0)
    end

    it "a REST session decision needs a user" do
      proposal = file_proposal(type: "feature")
      expect { proposal.approve!(nil, origin: Ai::ApprovalDecision::REST_SESSION) }.to raise_error(Ai::AgentProposals::Decision::Refused)
    end

    it "an impersonation or account-switch session is not an admitted door" do
      proposal = file_proposal(type: "feature")
      expect { proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_OTHER) }.to raise_error(Ai::AgentProposals::Decision::Refused, /from your own session/)
    end

    it "an undeclared internal caller is refused; a declared one is audited as system with its principal" do
      proposal = file_proposal(type: "configuration", changes: { "source" => "gitops" })
      expect { proposal.approve!(nil, origin: "internal", principal: "someone_else") }.to raise_error(Ai::AgentProposals::Decision::Refused)
      expect { proposal.approve!(nil, origin: "internal") }.to raise_error(Ai::AgentProposals::Decision::Refused)

      proposal.approve!(nil, origin: "internal", principal: "gitops_reconciler")
      row = audit_rows(proposal, "ai.proposal.approved").sole
      expect(row.source).to eq("system")
      expect(row.user_id).to be_nil
      expect(row.metadata).to include("principal" => "gitops_reconciler", "origin" => "internal")
    end

    it "a gateway chain timeout_action approve (no decision row) leaves the proposal pending" do
      proposal = file_proposal(type: "feature")
      request = instance_double(Ai::ApprovalRequest, status: "approved", decisions: double(order: double(last: nil)))

      expect(proposal.on_approval_decision(request)).to eq(Ai::ApprovalRequest::DISPATCH_NOOP)
      expect(proposal.reload.status).to eq("pending_review")
      expect(Ai::RalphTask.count).to eq(0)
    end

    it "a real timeout-approved gateway request never approves the proposal" do
      allow(Ai::Approvals::Gateway).to receive(:governance_enabled?).and_return(true)
      proposal = file_proposal(type: "feature")
      request = Ai::Approvals::Gateway.new(account: account).request!(approvable: proposal, kind: "agent_proposal").approval_request

      request.approve! # what a chain's timeout_action "approve" does: a status flip with no decision

      expect(proposal.reload.status).to eq("pending_review")
      expect(proposal.handoff_kind).to be_nil
    end

    it "a timeout-rejected gateway request makes the proposal expired, not rejected" do
      proposal = file_proposal(type: "feature")
      request = instance_double(Ai::ApprovalRequest, status: "rejected", decisions: double(order: double(last: nil)))

      proposal.on_approval_decision(request)
      expect(proposal.reload.status).to eq("expired")
    end
  end

  describe "the campaign handoff principal can only propose" do
    let(:handoff) { Ai::Campaigns::Authorization::AGENT_PROPOSAL_HANDOFF }

    it "cannot approve, queue, reject, edit or spawn a campaign proposal" do
      campaign_proposal = Ai::CampaignProposal.propose!(account: account, title: "T", objective: "O", principal: handoff)

      expect { campaign_proposal.approve!(nil, principal: handoff) }.to raise_error(Ai::Campaigns::Authorization::Refused, /may only propose/)
      expect { campaign_proposal.queue!(nil, principal: handoff) }.to raise_error(Ai::Campaigns::Authorization::Refused)
      expect { campaign_proposal.reject!(nil, principal: handoff) }.to raise_error(Ai::Campaigns::Authorization::Refused)
      expect { campaign_proposal.update_fields!(principal: handoff, title: "x") }.to raise_error(Ai::Campaigns::Authorization::Refused)
      expect(campaign_proposal.reload.status).to eq("proposed")

      campaign_proposal.update_columns(status: "approved")
      expect { Ai::CampaignProposals::SpawnService.new(account: account, principal: handoff).spawn!(campaign_proposal) }
        .to raise_error(Ai::Campaigns::Authorization::Refused)
      expect(Ai::Campaign.count).to eq(0)
    end
  end

  describe "an abandoned handoff" do
    it "audits ai.proposal.handoff_abandoned when the campaign proposal it opened is rejected" do
      proposal = file_proposal(type: "architecture")
      proposal.approve!(reviewer, origin: Ai::ApprovalDecision::REST_SESSION)
      campaign_proposal = Ai::CampaignProposal.find(proposal.reload.handoff_id)

      campaign_reviewer = user_with_permissions("ai.campaigns.manage", account: account)
      campaign_proposal.reject!(campaign_reviewer, reason: "not now")

      row = audit_rows(proposal, "ai.proposal.handoff_abandoned").sole
      expect(row.user_id).to eq(campaign_reviewer.id)
      expect(row.metadata).to include("campaign_proposal_id" => campaign_proposal.id, "reason" => "not now")
      expect(proposal.reload.status).to eq("approved")
    end
  end
end
