# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::FederationTool do
  let(:account) { create(:account) }
  subject(:tool) { described_class.new(account: account) }

  # IMP-019fe13d: this class inherited BaseTool.definition, which raises. The
  # registrar calls .definition outside its per-tool rescue, so the miss took
  # down registration for every tool and with it every McpChannel subscribe.
  describe ".definition" do
    it "is implemented rather than inheriting BaseTool's raise" do
      expect { described_class.definition }.not_to raise_error
    end

    it "names the tool and declares the action parameter the registrar keys multi-action tools on" do
      expect(described_class.definition[:name]).to eq("federation")
      expect(described_class.definition[:parameters]).to have_key(:action)
    end

    it "declares a parameter for every parameter its actions accept" do
      declared = described_class.definition[:parameters].keys
      action_params = described_class.action_definitions.values.flat_map { |a| a[:parameters].keys }.uniq
      expect(declared).to include(*action_params)
    end
  end

  describe "#federation_invoke_tool" do
    it "proxies to the resolved partner and returns the remote result" do
      partner = create(:federation_partner, :active, account: account)
      allow_any_instance_of(FederationPartner).to receive(:invoke_remote_tool)
        .with(tool: "system_list_templates", arguments: {})
        .and_return({ success: true, result: { "templates" => [] } })

      result = tool.execute(params: {
        action: "federation_invoke_tool", partner_id: partner.id, tool: "system_list_templates"
      })

      expect(result[:success]).to be true
      expect(result[:data][:remote_result]).to eq({ "templates" => [] })
      expect(result[:data][:partner_id]).to eq(partner.id)
    end

    it "cannot reach a partner in another account" do
      other = create(:federation_partner, :active, account: create(:account))
      result = tool.execute(params: { action: "federation_invoke_tool", partner_id: other.id, tool: "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end

    it "requires a tool name" do
      partner = create(:federation_partner, :active, account: account)
      result = tool.execute(params: { action: "federation_invoke_tool", partner_id: partner.id })
      expect(result[:error]).to match(/tool is required/)
    end

    it "surfaces a remote error" do
      partner = create(:federation_partner, :active, account: account)
      allow_any_instance_of(FederationPartner).to receive(:invoke_remote_tool)
        .and_return({ success: false, error: "boom" })

      result = tool.execute(params: { action: "federation_invoke_tool", partner_id: partner.id, tool: "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to eq("boom")
    end

    it "resolves a partner by organization_id" do
      partner = create(:federation_partner, :active, account: account)
      allow_any_instance_of(FederationPartner).to receive(:invoke_remote_tool)
        .and_return({ success: true, result: "ok" })

      result = tool.execute(params: {
        action: "federation_invoke_tool", organization_id: partner.organization_id, tool: "x"
      })
      expect(result[:success]).to be true
    end
  end

  describe "#federation_list_partners" do
    it "lists only the caller account's active partners" do
      mine = create(:federation_partner, :active, account: account)
      create(:federation_partner, :pending, account: account)
      create(:federation_partner, :active, account: create(:account))

      result = tool.execute(params: { action: "federation_list_partners" })
      expect(result[:data][:partners].map { |p| p[:id] }).to eq([ mine.id ])
    end
  end

  it "rejects an unknown action" do
    expect(tool.execute(params: { action: "nope" })[:error]).to match(/Unknown federation action/)
  end

  it "refuses to run for a restricted principal (a peer must not drive outbound federation)" do
    partner = create(:federation_partner, :active, account: account)
    restricted = described_class.new(account: account)
    restricted.instance_authorized = true # marks a grant-gated instance/federation caller

    result = restricted.execute(params: {
      action: "federation_invoke_tool", partner_id: partner.id, tool: "system_list_templates"
    })
    expect(result[:success]).to be false
    expect(result[:error]).to match(/not available to a federated or instance principal/)
  end

  # === THE GOVERNANCE CHOKEPOINT (IMP-149b35e5f16f, APO-1e prerequisite) ===
  #
  # This class used to define its own #execute and never call super, so every
  # call it served skipped BaseTool#execute entirely: the declaration lookup
  # (its two declare_action rows governed nothing), the instance deny overlay
  # (IMP-0e6b216de843) and #validate_params!. It is the tool that proxies
  # ARBITRARY remote tool names, so the fail-closed flip could not honestly
  # read the declaration equality as coverage while it sat outside.
  #
  # The dispatch body now lives in #call, which BaseTool#execute reaches only
  # after those three controls have run.
  describe "routing through BaseTool#execute" do
    it "does not override #execute" do
      expect(described_class.instance_method(:execute).owner).to eq(Ai::Tools::BaseTool)
    end

    it "arms the instance deny overlay: a destroy-shaped action is refused by NAME, not by the tool's own body" do
      # The structural refusal below returns an error envelope. The overlay is
      # a RAISE, and it must win — it is the last control on an instance
      # principal and it is unconditional. Reaching it at all proves
      # BaseTool#execute ran before any of this tool's own code.
      restricted = described_class.new(account: account)
      restricted.instance_authorized = true

      expect {
        restricted.execute(params: { action: "federation_revoke_partner" })
      }.to raise_error(Mcp::ProtocolService::PermissionDeniedError, /destroy-shaped/)
    end

    it "runs #validate_params!: the tool's required :action parameter is enforced" do
      expect { tool.execute(params: {}) }
        .to raise_error(ArgumentError, /Missing required parameters: action/)
    end

    # NOT an oracle for the routing fix — it is green with the override back in
    # place, and it is here to say so. It records the state APO-1e inherits:
    # both declarations exist and both are still NON-ENFORCING (`mutating:`
    # alone), so #execute takes `return call(params)` and the body below is
    # what answers. The moment APO-1e adds the category/executor/context/
    # on_proceed quartet this goes red, which is the intended handoff signal —
    # and the example after it is what keeps the refusal correct across that
    # flip.
    it "leaves both federation declarations non-enforcing until APO-1e wires the gate" do
      probe = Ai::Tools::BaseTool.new(account: nil)

      described_class.action_definitions.each_key do |action|
        declaration = described_class.declared_action(action)
        expect(declaration).to be_present, "#{action} has no declare_action row"
        expect(probe.send(:gated_action?, declaration)).to be(false)
      end
    end

    # THE HOIST (review F1). A gated action returns from BaseTool#execute's gate
    # branch and never enters #call, so a refusal that lives only in #call is
    # deleted by the act of declaring the action — "a privilege escalation
    # introduced by a safety control", in base_tool.rb's own words. Simulated
    # here by making the declaration gated, which is exactly what APO-1e will
    # do to `federation_invoke_tool`.
    it "refuses a restricted principal even once the action is GATED, via #authorization_error" do
      restricted = described_class.new(account: account)
      restricted.instance_authorized = true
      allow_any_instance_of(Ai::Tools::BaseTool).to receive(:gated_action?).and_return(true)
      # Would raise if the gate were reached; the refusal must come first.
      allow_any_instance_of(Ai::Tools::BaseTool)
        .to receive(:run_through_autonomy_gate) { raise "gate reached: refusal was bypassed" }

      result = restricted.execute(params: { action: "federation_invoke_tool", tool: "system_list_nodes" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not available to a federated or instance principal/)
    end
  end
end
