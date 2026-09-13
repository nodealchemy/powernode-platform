# frozen_string_literal: true

require "rails_helper"

# IMP-70db2b60bfb3 — a SiteSetting WRITE over MCP goes through the autonomy
# gate, and a PROTECTED key is a person's decision.
#
# IMP-7723206bc137 made allow-listed settings writable over MCP, but the write
# ran directly: any caller holding admin.access, including an agent acting as
# its creator, changed a control-plane knob with no approval, no policy and no
# person. Operator direction: the write is gated by Ai::AutonomyGate, and a
# protected key (the one that arms INV-1) is approved only by a user principal
# from their own session. Arming INV-1 is NOT part of this change.
#
# Every example asserts the row as well as the envelope: a refusal that writes
# anyway passes an envelope-shaped assertion.
RSpec.describe Ai::Tools::SiteSettingTool, "autonomy gate" do
  let(:account) { create(:account) }
  let!(:requester) { create(:user, account: account, permissions: [ "admin.access" ]) }
  let(:confirmer) { create(:user, account: account, permissions: [ "admin.access", "ai.autonomy.approve" ]) }

  let(:plain_key) { "zz_gate_spec_plain_key" }
  let(:protected_key) { "zz_gate_spec_protected_key" }

  before do
    described_class.register_key(plain_key, setting_type: "string", description: "gate spec plain key")
    described_class.register_key(protected_key, setting_type: "string", description: "gate spec protected key",
                                                protected: true)
  end

  after { ::Mcp::Principal.reset! }

  def tool_for(user: requester, origin: "mcp_oauth")
    tool = described_class.new(account: account, user: user)
    tool.call_origin = origin
    tool
  end

  def workflow = Ai::Autonomy::ApprovalWorkflowService.new(account: account)

  def pending_operation(result)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true)
    Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
  end

  describe "site_setting_set (an ordinary key)" do
    it "parks behind the gate instead of writing, when no policy proceeds it" do
      SiteSetting.set(plain_key, "before")

      operation = pending_operation(
        tool_for.execute(params: { action: "site_setting_set", key: plain_key, value: "after" })
      )

      expect(operation.action_category).to eq("platform.site_setting.write")
      expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
      expect(SiteSetting.get(plain_key)).to eq("before")
    end

    it "writes once an operator's approval completes the parked request" do
      SiteSetting.set(plain_key, "before")
      operation = pending_operation(
        tool_for.execute(params: { action: "site_setting_set", key: plain_key, value: "after" })
      )

      expect(workflow.approve(request: operation.approval_request, approver: confirmer,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)

      expect(SiteSetting.get(plain_key)).to eq("after")
      expect(operation.reload.status).to eq("completed")
    end

    it "writes directly when an operator's policy auto-approves the category" do
      Ai::InterventionPolicy.create!(account: account, action_category: "platform.site_setting.write",
                                     scope: "global", policy: "auto_approve", priority: 5, is_active: true)

      result = tool_for.execute(params: { action: "site_setting_set", key: plain_key, value: "auto" })

      expect(result[:success]).to be(true), result.inspect
      expect(SiteSetting.get(plain_key)).to eq("auto")
    end

    it "refuses a PROTECTED key outright, parks nothing, and names the verb that carries it" do
      SiteSetting.set(protected_key, "before")

      result = nil
      expect {
        result = tool_for.execute(params: { action: "site_setting_set", key: protected_key, value: "after" })
      }.not_to change(Ai::DeferredOperation, :count)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("site_setting_set_protected")
      expect(SiteSetting.get(protected_key)).to eq("before")
    end
  end

  describe "site_setting_set_protected (a protected key)" do
    it "parks for a person even under an auto_approve policy, and does not write" do
      Ai::InterventionPolicy.create!(account: account, action_category: "platform.site_setting.protected_write",
                                     scope: "global", policy: "auto_approve", priority: 5, is_active: true)
      SiteSetting.set(protected_key, "before")

      operation = pending_operation(
        tool_for.execute(params: { action: "site_setting_set_protected", key: protected_key, value: "after" })
      )

      expect(operation.approval_request.requires_human_session?).to be(true)
      expect(SiteSetting.get(protected_key)).to eq("before")
    end

    it "writes only on a person's own-session approval, and records that person as the writer" do
      operation = pending_operation(
        tool_for.execute(params: { action: "site_setting_set_protected", key: protected_key, value: "armed" })
      )

      expect(workflow.approve(request: operation.approval_request, approver: confirmer,
                              origin: "mcp_oauth")).to be(false)
      expect(SiteSetting.find_by(key: protected_key)).to be_nil

      expect(workflow.approve(request: operation.approval_request, approver: confirmer,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)

      expect(SiteSetting.get(protected_key)).to eq("armed")
      expect(AuditLog.where(action: "update_site_setting").last.user_id).to eq(confirmer.id)
    end

    it "refuses an ordinary key, so a human-only park cannot launder a plain write" do
      result = tool_for.execute(params: { action: "site_setting_set_protected", key: plain_key, value: "x" })

      expect(result[:success]).to be(false)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(SiteSetting.find_by(key: plain_key)).to be_nil
    end
  end

  describe "principals that may not write at all" do
    it "refuses an instance principal on both verbs without parking" do
      %w[site_setting_set site_setting_set_protected].each do |action|
        key = action == "site_setting_set" ? plain_key : protected_key
        node_tool = described_class.new(account: account)
        node_tool.instance_authorized = true

        result = node_tool.execute(params: { action: action, key: key, value: "node" })

        expect(result[:success]).to be(false), "#{action}: #{result.inspect}"
      end
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(SiteSetting.where(key: [ plain_key, protected_key ])).to be_empty
    end

    it "refuses an in-process internal caller on both verbs without parking" do
      %w[site_setting_set site_setting_set_protected].each do |action|
        key = action == "site_setting_set" ? plain_key : protected_key
        result = described_class.new(account: account, internal: true)
                                .execute(params: { action: action, key: key, value: "reconciler" })

        expect(result[:success]).to be(false), "#{action}: #{result.inspect}"
      end
      expect(Ai::DeferredOperation.count).to eq(0)
    end
  end

  describe "the key registry" do
    it "records protection as part of a key's shape, so two owners cannot disagree about it" do
      expect(described_class.operator_configurable_keys[protected_key]).to include(protected: true)
      expect {
        described_class.register_key(protected_key, setting_type: "string", description: "gate spec protected key")
      }.to raise_error(ArgumentError, /different shape/)
    end

    it "is reachable from the platform tool registry under the protected verb" do
      expect(Ai::Tools::PlatformApiToolRegistry::TOOLS["site_setting_set_protected"]).to eq("Ai::Tools::SiteSettingTool")
    end
  end
end
