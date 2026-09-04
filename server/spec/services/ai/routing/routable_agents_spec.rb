# frozen_string_literal: true

require "rails_helper"

# ONE definition of "routable agent", shared by the Claude Code exporter
# (Ai::ClaudeExport::AgentSkeletonSync) and the router
# (Ai::Routing::AgentRouterService): active, not an mcp_client identity, the
# account's own row winning over a same-slug canonical.
RSpec.describe Ai::Routing::RoutableAgents do
  let(:account) { create(:account) }

  it ".for(account_id) unions the account's rows with the canonicals, account override winning by slug" do
    canonical = create(:ai_agent, :global, is_system: true, name: "Code Reviewer")
    override = create(:ai_agent, account: account, name: "Code Reviewer")
    other_canonical = create(:ai_agent, :global, is_system: true, name: "Planner")
    create(:ai_agent, :mcp_client, account: account)
    create(:ai_agent, :inactive, account: account, name: "Paused")

    agents = described_class.for(account.id)

    expect(agents.map(&:id)).to contain_exactly(override.id, other_canonical.id)
    expect(agents.map(&:id)).not_to include(canonical.id)
  end

  it ".canonical returns GLOBAL is_system active non-mcp_client agents only, sorted by key" do
    b = create(:ai_agent, :global, is_system: true, name: "Zeta Agent")
    a = create(:ai_agent, :global, is_system: true, name: "Alpha Agent")
    create(:ai_agent, :global, is_system: false, name: "Ad hoc")
    create(:ai_agent, account: account, name: "Mine")

    expect(described_class.canonical.map(&:id)).to eq([ a.id, b.id ])
  end

  it ".key is the slug (filesystem-safe, the CC subagent_type)" do
    agent = create(:ai_agent, account: account, name: "Fleet Autonomy")

    expect(described_class.key(agent)).to eq(agent.slug)
  end
end
