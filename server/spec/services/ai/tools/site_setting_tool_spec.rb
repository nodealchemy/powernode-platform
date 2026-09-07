# frozen_string_literal: true

require "rails_helper"

# IMP-7723206bc137 — the MCP catalog exposed no verb to read or write a
# SiteSetting, so every DB-driven global knob was configurable in principle and
# unreachable in practice without shell access. The concrete block: the single
# key that arms System::Autonomy::SelfManagementFence (INV-1, no
# self-management) could not be set through the interface the platform
# advertises as its control surface.
#
# The verb is deliberately ALLOW-LISTED rather than a generic key/value setter.
# Two reasons, and the second is the one that decided the shape:
#
#   1. SiteSetting has no "secret" setting_type to redact on — the enum is
#      string/text/boolean/integer/json (site_setting.rb:19). There is no
#      marker a redaction rule could key on, so "return every key except the
#      secret ones" is not expressible. An allowlist inverts that: a key is
#      readable because someone put it there, not because nothing flagged it.
#   2. A tool RESULT is not a private channel. Ai::AgentToolBridgeService
#      persists a preview into ai_messages.processing_metadata and forwards the
#      full JSON to the model provider on the next turn — the disclosure sink
#      Ai::Tools::DiskImageOperatorTool documents at length. A generic getter
#      would be a standing exfiltration path for whatever an operator later
#      stores in a SiteSetting.
RSpec.describe Ai::Tools::SiteSettingTool do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: admin) }

  # The REST twin gates on `admin.access` OR `settings.manage`
  # (site_settings_controller.rb:5 -> require_admin_access("settings.manage")).
  # Mirroring it exactly is the task's requirement, so both spellings are
  # exercised rather than assumed equivalent.
  before do
    allow(admin).to receive(:has_permission?).and_return(false)
    allow(admin).to receive(:has_permission?).with("admin.access").and_return(true)
  end

  def call(action, **params)
    tool.execute(params: { action: action }.merge(params))
  end

  describe "the allowlist" do
    it "carries the key this task exists to make reachable, registered by the extension that owns it" do
      expect(described_class.operator_configurable_keys).to include("self_hosting_node_id")
    end

    # Core registers no key of its own (see the class comment — an earlier
    # draft registered the autonomy enable-switch and that was a widening), so
    # the mechanism is exercised through a key registered here rather than
    # through the extension's, which would make a CORE spec depend on an
    # extension being installed.
    it "serves a key registered by any owner, not only the extension's" do
      described_class.register_key(
        "zz_spec_core_owned_key", setting_type: "string", description: "core-owned fixture key"
      )

      result = call("site_setting_set", key: "zz_spec_core_owned_key", value: "v1")

      expect(result[:success]).to be true
      expect(SiteSetting.get("zz_spec_core_owned_key")).to eq("v1")
    end

    # The seam exists so core never names an extension's configuration
    # vocabulary — core-purity-check.sh blocked the first draft for exactly
    # that. Re-registering the same key with a different shape must raise
    # rather than let load order decide which owner wins.
    it "refuses a conflicting re-registration instead of silently taking one" do
      expect {
        described_class.register_key("self_hosting_node_id", setting_type: "integer", description: "wrong")
      }.to raise_error(ArgumentError, /already registered with a different shape/)
    end

    it "refuses a setting_type SiteSetting's own validation would reject" do
      expect {
        described_class.register_key("zz_bogus_key", setting_type: "secret", description: "x")
      }.to raise_error(ArgumentError, /not one of/)
    end

    it "refuses to read a key that is not on it" do
      SiteSetting.set("stripe_secret_key", "sk_live_not_a_real_key", setting_type: "string")

      result = call("site_setting_get", key: "stripe_secret_key")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not operator-configurable/i)
      # The refusal must not leak the value it refused to serve.
      expect(result.to_json).not_to include("sk_live_not_a_real_key")
    end

    it "refuses to write a key that is not on it, and the row is unchanged" do
      SiteSetting.set("site_name", "Powernode", setting_type: "string")

      result = call("site_setting_set", key: "site_name", value: "Pwned")

      expect(result[:success]).to be false
      expect(SiteSetting.get("site_name")).to eq("Powernode")
    end
  end

  describe "site_setting_get" do
    it "returns the typed value for an allow-listed key" do
      # Synthetic id. An earlier version of this fixture used THIS DEPLOYMENT'S
      # real ops-hub node UUID, which is a deployment-local fact in a tracked
      # file published to a public mirror. The value here must never be a real
      # node id — the tool does not validate it, so any well-formed uuid works.
      SiteSetting.set("self_hosting_node_id", "019f7c2d-0000-7000-8000-000000000001")

      result = call("site_setting_get", key: "self_hosting_node_id")

      expect(result[:success]).to be true
      expect(result[:data][:value]).to eq("019f7c2d-0000-7000-8000-000000000001")
    end

    it "reports an unset allow-listed key as unset rather than erroring" do
      result = call("site_setting_get", key: "self_hosting_node_id")

      expect(result[:success]).to be true
      expect(result[:data][:value]).to be_nil
      expect(result[:data][:set]).to be false
    end
  end

  describe "site_setting_set" do
    it "writes an allow-listed key" do
      result = call("site_setting_set", key: "self_hosting_node_id", value: "node-abc")

      expect(result[:success]).to be true
      expect(SiteSetting.get("self_hosting_node_id")).to eq("node-abc")
    end

    # site_setting_set is declared `audit: true`, so BaseTool writes a
    # FAIL-CLOSED Ai::SensitiveAccessAudit row before #call and refuses the
    # action outright if the row does not persist. That is the ledger; this
    # tool writes no second one.
    it "writes a fail-closed sensitive-access row for the REQUEST and an outcome row for the WRITE" do
      call("site_setting_set", key: "self_hosting_node_id", value: "node-abc")

      requested = AuditLog.where(action: "mcp.tools.sensitive_access").order(:created_at).last
      expect(requested.user_id).to eq(admin.id)
      expect(requested.metadata.to_s).to include("self_hosting_node_id")

      written = AuditLog.where(action: "update_site_setting").order(:created_at).last
      expect(written).to be_present
      expect(written.user_id).to eq(admin.id)
      expect(written.metadata["setting_key"]).to eq("self_hosting_node_id")
    end

    # The two rows answer different questions, and conflating them was a real
    # defect in an earlier draft: the sensitive-access row is written BEFORE
    # this tool's own authorization runs, so a REFUSED call leaves one too. If
    # that were the only ledger, a forensic query for a key would show a
    # request from a principal that was refused and read as a write.
    it "records no outcome row when the write was refused" do
      SiteSetting.set("self_hosting_node_id", "original-node")
      node_tool = described_class.new(account: account, user: nil)
      node_tool.instance_authorized = true

      node_tool.execute(
        params: { action: "site_setting_set", key: "self_hosting_node_id", value: "attacker-node" }
      )

      expect(AuditLog.where(action: "update_site_setting")).to be_empty
    end

    # The row records WHICH key moved, never WHAT it moved to. Audit rows are
    # read by more people than hold the permission to write settings, and for
    # this tool the value IS the sensitive material.
    it "does not put the value in the audit row" do
      call("site_setting_set", key: "self_hosting_node_id", value: "node-secret-value")

      expect(AuditLog.pluck(:metadata).to_json).not_to include("node-secret-value")
    end
  end

  describe "an instance principal (mTLS node cert, no User)" do
    # The prevailing ladder in sibling tools is `return true if
    # instance_authorized?` — an instance principal whose tool name cleared
    # Mcp::Principal#may_invoke? is normally ALLOWED. This verb refuses it
    # explicitly, and that refusal is the point rather than an oversight: the
    # keys here configure the control plane, and self_hosting_node_id in
    # particular is the key that decides whether a node may be acted upon by
    # the plane it hosts. A node that can write it can disarm the fence that
    # exists to protect the plane from itself (INV-1).
    let(:instance_tool) do
      t = described_class.new(account: account, user: nil)
      t.instance_authorized = true
      t
    end

    it "refuses to write, and the row is unchanged" do
      SiteSetting.set("self_hosting_node_id", "original-node")

      result = instance_tool.execute(
        params: { action: "site_setting_set", key: "self_hosting_node_id", value: "attacker-node" }
      )

      expect(result[:success]).to be false
      # THE ORACLE IS THE ROW, not the error. A refusal that returns an error
      # and writes anyway passes an error-shaped assertion.
      expect(SiteSetting.get("self_hosting_node_id")).to eq("original-node")
    end

    it "creates no row when the key did not exist" do
      expect {
        instance_tool.execute(
          params: { action: "site_setting_set", key: "self_hosting_node_id", value: "attacker-node" }
        )
      }.not_to change(SiteSetting, :count)

      expect(SiteSetting.find_by(key: "self_hosting_node_id")).to be_nil
    end

    it "refuses to read" do
      SiteSetting.set("self_hosting_node_id", "original-node")

      result = instance_tool.execute(
        params: { action: "site_setting_get", key: "self_hosting_node_id" }
      )

      expect(result[:success]).to be false
      expect(result.to_json).not_to include("original-node")
    end
  end

  describe "a user without the permission" do
    let(:nobody) { create(:user, account: account) }
    let(:nobody_tool) { described_class.new(account: account, user: nobody) }

    before { allow(nobody).to receive(:has_permission?).and_return(false) }

    it "refuses to write, and the row is unchanged" do
      SiteSetting.set("self_hosting_node_id", "original-node")

      result = nobody_tool.execute(
        params: { action: "site_setting_set", key: "self_hosting_node_id", value: "new-node" }
      )

      expect(result[:success]).to be false
      expect(SiteSetting.get("self_hosting_node_id")).to eq("original-node")
    end
  end

  # McpPlatformToolRegistrar.enforce_permission! (:672-693) requires
  # REQUIRED_PERMISSION conjunctively for every user principal BEFORE the tool
  # is constructed, so that constant — not the in-tool OR-ladder — is the real
  # floor on a live MCP call. It must name a permission the catalog actually
  # has, or the verb is reachable only through the system.admin shortcut.
  describe "the permission floor the MCP registrar enforces" do
    # RolePermission#permission_must_exist_in_catalog means an uncatalogued
    # name can be held by NO role — has_permission? would then be true only
    # through the system.admin shortcut, silently narrowing the verb to one
    # principal. "settings.manage", which an earlier draft named here, is
    # exactly such a name.
    it "names a permission that exists in the catalog" do
      expect(Permissions.permission_exists?(described_class::REQUIRED_PERMISSION)).to be true
    end

    it "names the rung that actually grants on the REST twin" do
      expect(described_class::REQUIRED_PERMISSION).to eq("admin.access")
    end

    it "keeps settings.manage in the widening ladder for when it is catalogued" do
      expect(described_class::GRANTING_PERMISSIONS).to include("settings.manage")
    end
  end

  describe "an in-process internal caller" do
    # `internal: true` is BaseTool's bypass for userless reconcilers. It is
    # refused here: the hub's own reconciler writing the key that decides
    # whether the hub may be acted upon is INV-1 self-management by the control
    # plane on itself.
    let(:internal_tool) { described_class.new(account: account, user: nil, internal: true) }

    it "refuses to write, and the row is unchanged" do
      SiteSetting.set("self_hosting_node_id", "original-node")

      result = internal_tool.execute(
        params: { action: "site_setting_set", key: "self_hosting_node_id", value: "reconciler-node" }
      )

      expect(result[:success]).to be false
      expect(SiteSetting.get("self_hosting_node_id")).to eq("original-node")
    end
  end

  describe "catalog surface" do
    it "declares both actions" do
      expect(described_class::ACTIONS).to contain_exactly("site_setting_get", "site_setting_set")
    end

    it "declares site_setting_set as mutating so the governance layer sees it" do
      expect(described_class.declared_action("site_setting_set")[:mutating]).to be true
    end

    it "is reachable from the platform tool registry under both action names" do
      registry = Ai::Tools::PlatformApiToolRegistry::TOOLS

      expect(registry["site_setting_get"]).to eq("Ai::Tools::SiteSettingTool")
      expect(registry["site_setting_set"]).to eq("Ai::Tools::SiteSettingTool")
    end
  end
end
