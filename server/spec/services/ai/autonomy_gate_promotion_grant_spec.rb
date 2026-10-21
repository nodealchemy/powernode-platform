# frozen_string_literal: true

require "rails_helper"

# Time-boxed promotion grants at the gate. A release.promote that would PARK
# (require_approval: a policy row, the unmatched default, or an environment
# escalation) proceeds instead when an active grant names this account, this
# agent, this category, this environment and this module — and only then. The
# grant never touches a block, the kill switch, or a human-only call.
RSpec.describe Ai::AutonomyGate, "promotion grants" do
  let(:account) { create(:account) }
  let(:granter) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:ops) { account.environments.find_by!(slug: "ops") }
  let(:prod) { account.environments.find_by!(slug: "prod") }
  let(:module_id) { SecureRandom.uuid }
  let(:version_id) { SecureRandom.uuid }

  before do
    stub_const("PromotionGrantSpecExecutor", Class.new do
      def self.execute(params, deferred_operation:)
        { success: true, data: { ran: true } }
      end
    end)
  end

  # The subject names the promotion's TARGET plane; by default it is the plane
  # the gate resolved, as the system extension's promote context builds it.
  def promote(agent: self.agent, environment: ops, subject: :default, account: self.account, **rest)
    if subject == :default
      subject = { module_id: module_id, version_id: version_id, environment_id: environment.id }
    end
    described_class.evaluate(
      action_category: "release.promote", executor_class: "PromotionGrantSpecExecutor",
      params: { tool_params: { module_id: module_id } }, account: account, agent: agent,
      environment: environment, grant_subject: subject, agent_initiated: true, **rest
    )
  end

  def grant!(**attrs)
    create(:ai_promotion_grant, account: account, granted_by: granter, agent: agent, environment: ops, **attrs)
  end

  # The live shape: ops promotion parks on a global require_approval row.
  before do
    Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "release.promote",
                                   policy: "require_approval", priority: 60, conditions: { "environments" => [ "ops" ] })
  end

  it "parks a protected-environment promotion when no grant exists" do
    result = promote
    expect(result).to be_pending
    expect(result.deferred_operation.promotion_grant_id).to be_nil
  end

  describe "with a matching grant" do
    let!(:grant) { grant!(max_uses: 2) }

    it "proceeds, counts the use, links the operation and audits the use" do
      result = promote

      expect(result).to be_proceed
      expect(result.result).to include(success: true)
      expect(result.promotion_grant).to eq(grant)
      expect(grant.reload.uses_count).to eq(1)

      op = result.deferred_operation.reload
      expect(op.status).to eq("completed")
      expect(op.promotion_grant_id).to eq(grant.id)
      expect(op.approval_request_id).to be_nil

      audit = AuditLog.where(account_id: account.id, action: "ai.promotion_grant.used").sole
      expect(audit.resource_id).to eq(grant.id)
      expect(audit.metadata).to include(
        "promotion_grant_id" => grant.id, "ai_agent_id" => agent.id, "module_id" => module_id,
        "version_id" => version_id, "environment_id" => ops.id, "environment_slug" => "ops",
        "deferred_operation_id" => op.id, "uses_count" => 1, "target_environment_id" => ops.id
      )
    end

    it "honours a module allowlist" do
      grant.destroy!
      grant!(module_ids: [ module_id ])
      expect(promote).to be_proceed
    end

    it "lifts an environment escalation too (prod is supervised)" do
      grant.destroy!
      grant!(environment: prod, max_uses: 1, module_ids: [ module_id ], expires_at: 2.hours.from_now)
      expect(promote(environment: prod)).to be_proceed
    end
  end

  describe "parks exactly as today when the grant does not match" do
    it "expired" do
      g = grant!
      g.update_columns(expires_at: 1.minute.ago)
      expect(promote).to be_pending
    end

    it "revoked" do
      grant!.revoke!(by: granter)
      expect(promote).to be_pending
    end

    it "exhausted" do
      g = grant!(max_uses: 1)
      expect(promote).to be_proceed
      expect(promote).to be_pending
      expect(g.reload.uses_count).to eq(1)
    end

    it "for another agent" do
      grant!
      expect(promote(agent: create(:ai_agent, account: account))).to be_pending
    end

    it "for another environment" do
      grant!(environment: account.environments.find_by!(slug: "staging"))
      expect(promote).to be_pending
    end

    it "for another module" do
      grant!(module_ids: [ SecureRandom.uuid ])
      expect(promote).to be_pending
    end

    it "for another account" do
      grant!
      other = create(:account)
      Ai::InterventionPolicy.create!(account: other, scope: "global", action_category: "release.promote",
                                     policy: "require_approval", priority: 60)
      result = promote(account: other, agent: create(:ai_agent, account: other),
                       environment: other.environments.find_by!(slug: "ops"))
      expect(result).to be_pending
    end

    it "with no grant subject from the caller (fail closed)" do
      grant!
      expect(promote(subject: nil)).to be_pending
    end

    it "with no agent" do
      grant!
      expect(promote(agent: nil)).to be_pending
    end

    it "with no use counted on any refusal" do
      g = grant!(module_ids: [ SecureRandom.uuid ])
      promote
      expect(g.reload.uses_count).to eq(0)
      expect(AuditLog.where(account_id: account.id, action: "ai.promotion_grant.used")).to be_empty
    end
  end

  describe "what a grant never overrides" do
    let!(:grant) { grant! }

    it "a block" do
      Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "release.promote",
                                     policy: "block", priority: 90)
      expect(promote).to be_blocked
      expect(grant.reload.uses_count).to eq(0)
    end

    it "the kill switch (emergency halt)" do
      allow(Ai::Autonomy::KillSwitchService).to receive(:halted_now?).with(account.id).and_return(true)
      expect(promote).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end

    it "a human-only call" do
      result = promote(requires_human_session: true)
      expect(result).to be_pending
      expect(result.approval_request.requires_human_session?).to be(true)
      expect(grant.reload.uses_count).to eq(0)
    end

    it "a category the operator lists as human-session-only" do
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(Ai::Approvals::HumanSessionPolicy::SETTING_KEY)
                                         .and_return([ "release.*" ])
      expect(promote).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end

    it "an account mark that requires a person's session" do
      Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "release.promote",
                                     policy: "require_approval", priority: 1,
                                     conditions: { Ai::Approvals::HumanSessionPolicy::CONDITION_KEY => true })
      expect(promote).to be_pending
      expect(grant.reload.uses_count).to eq(0)
    end
  end
  # MEDIUM-3: a grant belongs to the agent, so the audit row must say who drove
  # the call that spent it.
  describe "the driving principal" do
    let(:driver) { create(:user, account: account) }

    it "is recorded on the used audit row: user, agent and door" do
      grant!
      promote(requested_by: driver, call_origin: Ai::Tools::CallOrigin::ALL.first)

      audit = AuditLog.where(account_id: account.id, action: "ai.promotion_grant.used").sole
      expect(audit.user_id).to eq(driver.id)
      expect(audit.metadata).to include(
        "driving_user_id" => driver.id, "driving_agent_id" => agent.id,
        "call_origin" => Ai::Tools::CallOrigin::ALL.first
      )
      expect(audit.metadata["principal"]).to include("kind")
    end

    describe "granter_driven_only" do
      let!(:grant) { grant!(granter_driven_only: true) }

      it "is spent when the granter drives the agent" do
        expect(promote(requested_by: granter)).to be_proceed
      end

      it "is not spent when someone else drives it" do
        expect(promote(requested_by: driver)).to be_pending
        expect(grant.reload.uses_count).to eq(0)
      end

      it "is not spent when no person drives it" do
        expect(promote).to be_pending
        expect(grant.reload.uses_count).to eq(0)
      end
    end
  end

  # LOW-2: the grant's plane must be the promotion's TARGET plane, not merely
  # the plane the gate escalated to (a prod instance_id can lift the gate plane).
  describe "the promotion's target environment" do
    it "must be the grant's plane" do
      grant!(environment: prod, max_uses: 1, module_ids: [ module_id ], expires_at: 2.hours.from_now)
      result = promote(environment: prod, subject: { module_id: module_id, version_id: version_id, environment_id: ops.id })
      expect(result).to be_pending
    end

    it "is required (fail closed)" do
      grant!
      expect(promote(subject: { module_id: module_id, version_id: version_id })).to be_pending
    end
  end
end
