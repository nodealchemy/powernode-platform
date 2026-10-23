# frozen_string_literal: true

require "rails_helper"

# Agent-requested, optionally session-bound promotion grants (series 1).
#
# An agent asks for a grant with frozen terms; the request parks as a
# human-only approval card; a person's own-session approval of that card
# issues the grant in that person's name with exactly those terms, bound (or
# not) to the requesting MCP session. Nothing else issues one.
RSpec.describe "Agent-requested promotion grants" do
  let(:account) { create(:account) }
  let(:granter) do
    create(:user, account: account,
                  permissions: %w[ai.agents.read ai.autonomy.approve ai.promotion_grants.manage ai.promotion_grants.read
                                  ai.agents.update])
  end
  let(:driver) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:agent) { create(:ai_agent, account: account, agent_type: "mcp_client", name: "Claude Code (spec) #1") }
  let(:ops) { account.environments.find_by!(slug: "ops") }
  let(:prod) { account.environments.find_by!(slug: "prod") }
  let(:module_id) { SecureRandom.uuid }
  let(:session) { McpSession.create!(user: driver, account: account, ai_agent: agent) }
  let(:catalog) do
    Class.new do
      def required_permission(category) = category == "release.promote" ? "ai.agents.update" : nil
      def subjects(**) = []
      def unknown_subject_ids(ids:, **) = []
    end.new
  end

  before do
    allow(Ai::PromotionGrants::Catalog).to receive(:provider).and_return(catalog)
    stub_const("GrantRequestSpecExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { success: true, data: { ran: true } }
    end)
    Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "release.promote",
                                   policy: "require_approval", priority: 60)
  end

  def tool(on_session: session, as_agent: agent)
    built = Ai::Tools::AgentAutonomyTool.new(account: account, user: driver, agent: as_agent,
                                             call_origin: Ai::Tools::CallOrigin::MCP_OAUTH)
    built.mcp_session = on_session if on_session
    built
  end

  def ask(on_session: session, **params)
    tool(on_session: on_session).execute(params: {
      action: "request_promotion_grant", environment: "ops", module_ids: [ module_id ], max_uses: 2,
      expires_in_hours: 3, reason: "ship the train", bind: "session"
    }.merge(params).with_indifferent_access)
  end

  def approve_own_session(approval, approver: granter)
    Ai::Autonomy::ApprovalWorkflowService.new(account: account)
      .approve(request: approval, approver: approver, origin: Ai::ApprovalDecision::REST_SESSION)
  end

  # The gate call a session-carrying tool makes: its park principal is minted
  # from the tool's own state, including the session it arrived on.
  def promote(on_session: session, as_agent: agent, category: "release.promote", **rest)
    principal = Ai::Approvals::ParkPrincipal.descriptor(
      user: driver, agent: as_agent, internal: false, instance_authorized: false, node_instance: nil,
      call_origin: Ai::Tools::CallOrigin::MCP_OAUTH, mcp_session_id: on_session&.id
    )
    Ai::AutonomyGate.evaluate(
      action_category: category, executor_class: "GrantRequestSpecExecutor",
      params: Ai::Approvals::ParkPrincipal.stamp({ tool_params: { module_id: module_id } }, principal),
      account: account, agent: as_agent, environment: ops, agent_initiated: true,
      grant_subject: { module_id: module_id, version_id: SecureRandom.uuid, environment_id: ops.id }, **rest
    )
  end

  def issued_grant!
    result = ask
    grant_request = Ai::PromotionGrantRequest.find(result[:promotion_grant_request][:id])
    expect(approve_own_session(grant_request.approval_request)).to be(true)
    grant_request.reload.promotion_grant
  end

  def audits(action) = AuditLog.where(account_id: account.id, action: action)

  describe "requesting" do
    it "parks a human-only card for the calling agent, bound to its session, and grants nothing" do
      result = ask

      expect(result[:success]).to be(true)
      grant_request = Ai::PromotionGrantRequest.find(result[:promotion_grant_request][:id])
      expect(grant_request).to have_attributes(ai_agent_id: agent.id, status: "pending", binding_kind: "mcp_session",
                                               binding_id: session.id, requested_by_id: driver.id)
      approval = grant_request.approval_request
      expect(approval.source_type).to eq("Ai::PromotionGrantRequest")
      expect(approval.source_id).to eq(grant_request.id)
      expect(approval.request_data["requires_human_session"]).to be(true)
      expect(approval.requires_human_session?).to be(true)
      expect(approval.request_data.dig("binding", "description")).to eq("bound to session #{session.id}")
      expect(Ai::PromotionGrant.count).to eq(0)
      expect(audits("ai.promotion_grant.requested").sole.resource_id).to eq(grant_request.id)
    end

    it "binds to nothing with bind: none" do
      result = ask(bind: "none")
      expect(Ai::PromotionGrantRequest.find(result[:promotion_grant_request][:id]))
        .to have_attributes(binding_kind: nil, binding_id: nil)
    end

    it "refuses bind: session off the caller's own live session" do
      expect(ask(on_session: nil)[:success]).to be(false)
      other = McpSession.create!(user: driver, account: account, ai_agent: create(:ai_agent, account: account))
      expect(ask(on_session: other)[:success]).to be(false)
      expect(Ai::PromotionGrantRequest.count).to eq(0)
    end

    it "never takes the agent from params: naming another agent is refused" do
      other_agent = create(:ai_agent, account: account)
      result = ask(agent_id: other_agent.id)
      expect(result[:success]).to be(false)

      result = ask(ai_agent_id: other_agent.id)
      expect(result[:success]).to be(false)
      expect(Ai::PromotionGrantRequest.where(ai_agent_id: other_agent.id)).to be_empty
      expect(Ai::PromotionGrantRequest.count).to eq(0)
    end

    it "never takes a binding id from params" do
      other = McpSession.create!(user: driver, account: account, ai_agent: agent)
      expect(ask(binding_id: other.id)[:success]).to be(false)
      expect(ask(mcp_session_id: other.id)[:success]).to be(false)
      expect(Ai::PromotionGrantRequest.count).to eq(0)
    end

    it "refuses a category that is not grantable" do
      result = ask(action_category: "system.instance_terminate")
      expect(result[:success]).to be(false)
      expect(result[:error]).to include("not a category a promotion grant may name")

      # Even when the operator's list names it: destructive is a hard exclusion.
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(Ai::PromotionGrants::Grantable::SETTING_KEY)
                                         .and_return(%w[release.promote system.instance_terminate])
      expect(ask(action_category: "system.instance_terminate")[:success]).to be(false)
      expect(Ai::PromotionGrantRequest.count).to eq(0)
    end

    it "refuses terms past the plane's bounds" do
      expect(ask(expires_in_hours: 25)[:success]).to be(false)
      expect(ask(environment: "prod", expires_in_hours: 5)[:success]).to be(false) # strict: 4h
      expect(ask(environment: "prod", max_uses: nil, expires_in_hours: 1)[:success]).to be(false)
      expect(Ai::PromotionGrantRequest.count).to eq(0)
    end

    it "dedupes a pending request on agent, environment and category" do
      first = ask
      again = ask(reason: "asking twice")
      expect(again[:deduped]).to be(true)
      expect(again[:promotion_grant_request][:id]).to eq(first[:promotion_grant_request][:id])
      expect(Ai::PromotionGrantRequest.count).to eq(1)
      expect(Ai::ApprovalRequest.where(source_type: "Ai::PromotionGrantRequest").count).to eq(1)
    end

    it "caps an agent at three pending requests" do
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(Ai::PromotionGrants::Grantable::SETTING_KEY)
                                         .and_return(%w[release.promote release.rollback])
      allow(catalog).to receive(:required_permission).and_return("ai.agents.update")

      expect(ask(environment: "ops")[:success]).to be(true)
      expect(ask(environment: "staging")[:success]).to be(true)
      expect(ask(environment: "ops", action_category: "release.rollback")[:success]).to be(true)
      fourth = ask(environment: "staging", action_category: "release.rollback")
      expect(fourth[:success]).to be(false)
      expect(fourth[:error]).to include("3 pending")
      expect(Ai::PromotionGrantRequest.pending.count).to eq(3)
    end
  end

  describe "issuing" do
    it "issues, on a person's own-session approval, exactly the requested terms in that person's name" do
      freeze_time do
        result = ask(granter_driven_only: false)
        grant_request = Ai::PromotionGrantRequest.find(result[:promotion_grant_request][:id])
        expect(approve_own_session(grant_request.approval_request)).to be(true)

        grant = grant_request.reload.promotion_grant
        expect(grant).to be_present
        expect(grant_request.status).to eq("issued")
        expect(grant.granted_by).to eq(granter)
        requested = grant_request.terms.except("lifetime_seconds")
        expect(grant.attributes.slice(*requested.keys)).to eq(requested)
        expect(grant.expires_at).to eq(Time.current + grant_request.lifetime_seconds)
        expect(grant.binding_kind).to eq("mcp_session")
        expect(grant.binding_id).to eq(session.id)
        created = audits("ai.promotion_grant.created").sole
        expect(created.user_id).to eq(granter.id)
        expect(created.metadata).to include("promotion_grant_request_id" => grant_request.id,
                                            "binding_kind" => "mcp_session", "binding_id" => session.id,
                                            "origin" => Ai::ApprovalDecision::REST_SESSION)
      end
    end

    it "a tool door can never issue: Ledger.issue! with the MCP_OAUTH origin refuses and records it" do
      expect do
        Ai::PromotionGrants::Ledger.issue!(
          account: account, granted_by: granter, origin: Ai::Tools::CallOrigin::MCP_OAUTH,
          attributes: { ai_agent_id: agent.id, environment_id: ops.id, action_category: "release.promote",
                        expires_at: 1.hour.from_now, reason: "through a tool" }
        )
      end.to raise_error(Ai::PromotionGrants::Ledger::Refused)
      expect(Ai::PromotionGrant.count).to eq(0)
      refused = audits("ai.promotion_grant.issue_refused").sole
      expect(refused.metadata).to include("origin" => Ai::Tools::CallOrigin::MCP_OAUTH, "ai_agent_id" => agent.id)
    end

    it "an approval recorded from a non-session door issues nothing and records the refusal" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      approval = grant_request.approval_request

      # The decision doors refuse it outright (it needs a person's own session)...
      expect(approval.record_decision!(approver: granter, decision: "approved",
                                       origin: Ai::Tools::CallOrigin::MCP_OAUTH)).to be(false)
      # ...and an approval that lands anyway, from a decision row naming a
      # tool door, still issues nothing.
      Ai::ApprovalDecision.create!(approval_request: approval, approver: granter, decision: "approved",
                                   step_number: 0, origin: Ai::Tools::CallOrigin::MCP_OAUTH)
      approval.approve!

      expect(grant_request.reload.status).to eq("refused")
      expect(grant_request.promotion_grant).to be_nil
      expect(Ai::PromotionGrant.count).to eq(0)
      expect(audits("ai.promotion_grant.issue_refused").sole.resource_id).to eq(grant_request.id)
    end

    it "approve-on-timeout issues nothing, even on a chain set to approve" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      approval = grant_request.approval_request
      approval.approval_chain.update!(timeout_action: "approve")
      approval.update_columns(expires_at: 1.minute.ago)

      approval.check_expiration!

      expect(approval.reload.status).not_to eq("approved")
      expect(grant_request.reload.status).to eq("rejected")
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "an approval no person made in their own session (an override) issues nothing" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      grant_request.approval_request.approve!

      expect(grant_request.reload.status).to eq("refused")
      expect(Ai::PromotionGrant.count).to eq(0)
      expect(audits("ai.promotion_grant.issue_refused").count).to eq(1)
    end

    it "re-checks the approver's granter permissions at approval time" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      approver = create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve ai.promotion_grants.manage])

      approval = grant_request.approval_request
      expect(approval.record_decision!(approver: approver, decision: "approved",
                                       origin: Ai::ApprovalDecision::REST_SESSION)).to be(false)
      expect(approval.decision_refusal).to include("ai.agents.update")
      expect(grant_request.reload.status).to eq("pending")
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "the requesting agent never decides its own request" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      approval = grant_request.approval_request
      expect(approval.requester_excluded?(approver: granter, origin: Ai::Tools::CallOrigin::MCP_OAUTH,
                                          agent: agent)).to be(true)
    end

    it "closes on rejection with nothing issued" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      Ai::Autonomy::ApprovalWorkflowService.new(account: account)
        .reject(request: grant_request.approval_request, approver: granter, origin: Ai::ApprovalDecision::REST_SESSION)

      expect(grant_request.reload.status).to eq("rejected")
      expect(Ai::PromotionGrant.count).to eq(0)
      expect(audits("ai.promotion_grant.request_closed").count).to eq(1)
    end

    it "issues nothing when the bound session ended before the approval" do
      grant_request = Ai::PromotionGrantRequest.find(ask[:promotion_grant_request][:id])
      session.update!(status: "expired")

      approve_own_session(grant_request.approval_request)

      expect(grant_request.reload.status).to eq("refused")
      expect(Ai::PromotionGrant.count).to eq(0)
    end
  end

  describe "spending a session-bound grant" do
    let!(:grant) { issued_grant! }

    it "is consumed by a call on that session" do
      result = promote
      expect(result).to be_proceed
      expect(result.promotion_grant).to eq(grant)
      used = audits("ai.promotion_grant.used").sole
      expect(used.metadata).to include("binding_kind" => "mcp_session", "binding_id" => session.id)
      expect(used.metadata["principal"]).to include("mcp_session_id" => session.id)
    end

    it "is not consumed by the same agent on another session" do
      other = McpSession.create!(user: driver, account: account, ai_agent: agent)
      expect(promote(on_session: other)).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end

    it "is not consumed by a call carrying no session" do
      expect(promote(on_session: nil)).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end

    it "stops when the session ends, and the end revokes it with an audit row" do
      session.update!(status: "expired")

      expect(promote).to be_pending
      expect(grant.reload).to be_revoked
      revoked = audits("ai.promotion_grant.revoked").sole
      expect(revoked.metadata).to include("revocation_reason" => "session_ended", "binding_id" => session.id)
    end

    it "stops when the session goes idle, and the idle sweep revokes it" do
      session.update_columns(last_activity_at: 2.days.ago)
      expect(promote).to be_pending

      McpSession.expire_idle!
      expect(grant.reload).to be_revoked
      expect(audits("ai.promotion_grant.revoked").sole.metadata["revocation_reason"]).to eq("session_ended")
    end

    it "the binding sweep revokes a grant whose session ended without a callback" do
      session.update_columns(status: "revoked", revoked_at: 1.hour.ago)
      expect(promote).to be_pending

      Ai::PromotionGrants::BindingSweep.sweep!
      expect(grant.reload).to be_revoked
      expect(audits("ai.promotion_grant.revoked").sole.metadata["revocation_reason"]).to eq("session_ended")
    end

    it "is paused, not revoked, while a revoked session is inside its reconnect grace" do
      session.update_columns(status: "revoked", revoked_at: 1.minute.ago)
      expect(promote).to be_pending
      Ai::PromotionGrants::BindingSweep.sweep!
      expect(grant.reload).not_to be_revoked
    end
  end

  describe "what a bound grant never overrides" do
    let!(:grant) { issued_grant! }

    it "a human-only call" do
      expect(promote(requires_human_session: true)).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end

    it "the kill switch" do
      allow(Ai::Autonomy::KillSwitchService).to receive(:halted_now?).with(account.id).and_return(true)
      expect(promote).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end

    # A grant that somehow names an excluded category (written before the
    # exclusion, or by hand) is still never spent, whatever the operator's list says.
    %w[sdwan.peer_key_rotate system.instance_terminate platform.site_setting.protected_write].each do |category|
      it "a #{category} call, even on the operator's list" do
        allow(SiteSetting).to receive(:get).and_call_original
        allow(SiteSetting).to receive(:get).with(Ai::PromotionGrants::Grantable::SETTING_KEY)
                                           .and_return([ "release.promote", category ])
        Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: category,
                                       policy: "require_approval", priority: 60)
        grant.update_columns(action_category: category)

        expect(promote(category: category)).to be_pending
        expect(grant.reload.uses_count).to eq(0)
      end
    end
  end

  describe "the grantable categories" do
    let(:grantable) { Ai::PromotionGrants::Grantable }

    it "default to release.promote" do
      expect(grantable.categories).to eq(%w[release.promote])
    end

    it "never admit a human-only or destructive declared action's category" do
      expect(grantable.hard_excluded?(Ai::Tools::SiteSettingTool::PROTECTED_WRITE_CATEGORY)).to be(true)
      expect(grantable.hard_excluded?("ai.intervention_policy.write")).to be(true)
      expect(grantable.hard_excluded?("release.promote")).to be(false)
    end
  end
end
