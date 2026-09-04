# frozen_string_literal: true

require "rails_helper"

# platform.route_task — the MCP face of Ai::Routing::AgentRouterService.
# Read-only (ai.agents.read), declared non-mutating, registered in the registry.
RSpec.describe Ai::Tools::AgentRoutingTool do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let(:user) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:tool) { described_class.new(account: account, user: user) }

  let!(:sdwan) do
    create(:ai_agent, account: account, provider: provider, agent_type: "monitor", name: "SDWAN Manager",
                      description: "Manages sdwan peers, route policies and overlays.")
  end
  let!(:cve) do
    create(:ai_agent, account: account, provider: provider, agent_type: "monitor", name: "CVE Responder",
                      description: "Triages CVEs and plans critical upgrades.")
  end

  it "is registered as route_task, read-gated on ai.agents.read and declared non-mutating" do
    expect(Ai::Tools::PlatformApiToolRegistry.all_tools["route_task"]).to eq("Ai::Tools::AgentRoutingTool")
    expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    expect(described_class.declared_actions.fetch("route_task")[:mutating]).to be false
    expect(described_class.action_definitions.keys).to eq([ "route_task" ])
  end

  it "returns the ranked candidates with reasons and the winner's subagent_type" do
    result = tool.execute(params: { action: "route_task",
                                    task_description: "attach a new sdwan peer and refresh the route policies" })

    expect(result[:success]).to be true
    data = result[:data]
    expect(data[:subagent_type]).to eq(sdwan.slug)
    expect(data[:winner]).to include(agent_id: sdwan.id, slug: sdwan.slug)
    expect(data[:candidates].map { |c| c[:slug] }).to include(sdwan.slug, cve.slug)
    expect(data[:candidates].first[:reasons].keys).to include(:capability, :domain, :tier, :cost, :trust)
    expect(data[:spawn_hint]).to include(%(subagent_type: "#{sdwan.slug}"))
  end

  it "requires task_description" do
    result = tool.execute(params: { action: "route_task" })

    expect(result[:success]).to be false
    expect(result[:error]).to include("task_description")
  end

  it "applies constraints: delegator, agent_type and limit" do
    delegator = create(:ai_agent, account: account, provider: provider, name: "Concierge", description: "chat")
    create(:ai_delegation_policy, account: account, agent: delegator, allowed_delegate_types: %w[monitor])

    result = tool.execute(params: { action: "route_task", task_description: "sdwan peers",
                                    constraints: { "delegator_slug" => delegator.slug, "agent_type" => "monitor", "limit" => 1 } })

    data = result[:data]
    expect(data[:candidates].size).to eq(1)
    expect(data[:candidates].map { |c| c[:agent_id] }).not_to include(delegator.id)
    expect(data[:delegation]).to include(policy_applied: true)
  end

  it "refuses a user without ai.agents.read" do
    no_perm = create(:user, account: account, permissions: [])

    result = described_class.new(account: account, user: no_perm).execute(params: { action: "route_task", task_description: "x" })

    expect(result[:success]).to be false
    expect(result[:error]).to include("ai.agents.read")
  end
end
