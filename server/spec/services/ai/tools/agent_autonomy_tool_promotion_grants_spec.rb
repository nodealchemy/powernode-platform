# frozen_string_literal: true

require "rails_helper"

# The MCP door onto promotion grants is READ-ONLY. No tool action creates,
# extends or un-revokes a grant, and the row itself refuses a create from any
# tool door — even one carrying the granter's own credential.
RSpec.describe "agent_autonomy MCP promotion grants" do
  let(:account) { create(:account) }
  let(:granter) do
    create(:user, account: account, permissions: %w[ai.agents.read ai.promotion_grants.manage ai.promotion_grants.read])
  end
  let(:agent) { create(:ai_agent, account: account) }
  let(:ops) { account.environments.find_by!(slug: "ops") }

  def run(tool_name, params = {}, user: granter)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{tool_name}", params: params, account: account, user: user
    )
  end

  it "lists this account's grants" do
    grant = create(:ai_promotion_grant, account: account, granted_by: granter, agent: agent, environment: ops)
    create(:ai_promotion_grant) # another account's

    result = run("list_promotion_grants")

    expect(result[:success]).to be(true)
    expect(result[:promotion_grants].map { |g| g[:id] }).to eq([ grant.id ])
    expect(result[:promotion_grants].first).to include(status: "active", environment_slug: "ops", ai_agent_id: agent.id)
  end

  it "filters to active grants" do
    create(:ai_promotion_grant, account: account, granted_by: granter, agent: agent).revoke!(by: granter)
    expect(run("list_promotion_grants", { "active" => true })[:promotion_grants]).to be_empty
  end

  it "needs a promotion-grant permission" do
    reader = create(:user, account: account, permissions: %w[ai.agents.read])
    outcome = begin
      run("list_promotion_grants", {}, user: reader)
    rescue ::Mcp::ProtocolService::PermissionDeniedError => e
      { success: false, error: e.message }
    end
    expect(outcome[:success]).to be(false)
  end

  it "registers no create, update or revoke verb for grants" do
    actions = Ai::Tools::AgentAutonomyTool.action_definitions.keys
    expect(actions).to include("list_promotion_grants")
    expect(actions.grep(/promotion_grant/)).to eq([ "list_promotion_grants" ])
    expect(Ai::Tools::PlatformApiToolRegistry::TOOLS.keys.grep(/promotion_grant/)).to eq([ "list_promotion_grants" ])
  end

  it "refuses smuggling a create through the list verb" do
    expect do
      run("list_promotion_grants", { "action" => "create_promotion_grant", "ai_agent_id" => agent.id })
    rescue StandardError
      nil
    end.not_to change(Ai::PromotionGrant, :count)
  end

  # The row is the last line: whatever server code a tool door reaches, a
  # create that names a tool origin — or none — is refused, granter's own
  # credential or not.
  it "refuses a create from every tool door, with the granter's own credential" do
    Ai::Tools::CallOrigin::ALL.each do |origin|
      grant = Ai::PromotionGrant.new(account: account, granted_by: granter, agent: agent, environment: ops,
                                     action_category: "release.promote", expires_at: 1.hour.from_now,
                                     reason: "via #{origin}", issuing_origin: origin)
      expect(grant.save).to be(false)
    end
    expect(Ai::PromotionGrant.count).to eq(0)
  end
end
