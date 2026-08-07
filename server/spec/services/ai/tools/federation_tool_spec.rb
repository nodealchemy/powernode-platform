# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::FederationTool do
  let(:account) { create(:account) }
  subject(:tool) { described_class.new(account: account) }

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
end
