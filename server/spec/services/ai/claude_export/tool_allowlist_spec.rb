# frozen_string_literal: true

require "rails_helper"

# HIER-P1B item 3 — the ONE place that maps a platform agent's tool access to
# the Claude Code `tools:` frontmatter allowlist. Mirrors the resolution order of
# AgentToolBridgeService#scope_to_tool_families (allowed_tools -> full_registry
# -> tool_families -> SiteSetting family defaults -> nothing), rendered as
# `mcp__powernode__platform_<action>` plus the CC built-ins the agent type needs.
RSpec.describe Ai::ClaudeExport::ToolAllowlist do
  let(:account) { create(:account) }

  def agent_with(tool_access: nil, agent_type: "assistant")
    metadata = tool_access.nil? ? {} : { "tool_access" => tool_access }
    create(:ai_agent, account: account, agent_type: agent_type, mcp_metadata: metadata)
  end

  def mcp_actions(tools)
    tools.select { |t| t.start_with?(described_class::MCP_PREFIX) }
         .map { |t| t.delete_prefix(described_class::MCP_PREFIX) }
  end

  describe ".for" do
    it "gives every agent Read/Grep/Glob, the bootstrap verbs and the self-report verb" do
      tools = described_class.for(agent_with)

      expect(tools).to include("Read", "Grep", "Glob")
      expect(tools).to include("mcp__powernode__platform_get_agent", "mcp__powernode__platform_get_skill_context",
                               "mcp__powernode__platform_record_agent_execution")
    end

    # HIER-P2H — ONE bootstrap set, shared with the runtime bridge
    # (Ai::Tools::BootstrapVerbs), so Claude Code and the platform agree on
    # what an agent always has. The self-report verb stays the exporter's own
    # addition: it is a write, and the shared set is read-only by contract.
    it "unions the platform's bootstrap set (Ai::Tools::BootstrapVerbs) plus the self-report verb into every skeleton" do
      expect(described_class::BOOTSTRAP_ACTIONS).to eq(Ai::Tools::BootstrapVerbs::ACTIONS + described_class::SELF_REPORT_ACTIONS)
      expect(described_class::SELF_REPORT_ACTIONS).to eq(%w[record_agent_execution])

      actions = mcp_actions(described_class.for(agent_with(tool_access: { "tool_families" => %w[docker_list] })))
      expect(actions).to include(*Ai::Tools::BootstrapVerbs::ACTIONS, "record_agent_execution")
    end

    it "adds Edit/Write/Bash only for code_assistant" do
      expect(described_class.for(agent_with(agent_type: "code_assistant"))).to include("Edit", "Write", "Bash")
      expect(described_class.for(agent_with(agent_type: "monitor"))).not_to include("Edit", "Write", "Bash")
    end

    it "gives a scope-less agent the platform READ verbs only (no mutating action)" do
      actions = mcp_actions(described_class.for(agent_with))

      expect(actions).to include("list_agents", "get_agent", "search_knowledge")
      expect(actions).not_to include("delete_agent", "create_agent", "emergency_halt")
    end

    it "returns nil (inherit everything — omit `tools:`) for a full_registry agent" do
      expect(described_class.for(agent_with(tool_access: { "full_registry" => true }))).to be_nil
    end

    it "honours an explicit allowed_tools whitelist, dropping unregistered names, keeping the bootstrap verbs" do
      tools = described_class.for(agent_with(tool_access: { "allowed_tools" => %w[search_knowledge no_such_action] }))
      actions = mcp_actions(tools)

      expect(actions).to match_array(%w[search_knowledge] | described_class::BOOTSTRAP_ACTIONS)
    end

    it "treats allowed_tools ['*'] as unscoped" do
      expect(described_class.for(agent_with(tool_access: { "allowed_tools" => [ "*" ] }))).to be_nil
    end

    it "expands tool_families by exact name or `<family>_` prefix, like the bridge" do
      actions = mcp_actions(described_class.for(agent_with(tool_access: { "tool_families" => %w[list_agents docker_list] })))

      expect(actions).to include("list_agents", "docker_list_hosts", "docker_list_containers")
      expect(actions).not_to include("docker_get_host", "delete_agent")
    end

    it "fails open to unscoped when the families match nothing (the bridge's rule: misconfiguration must not disarm)" do
      expect(described_class.for(agent_with(tool_access: { "tool_families" => %w[no_such_family] }))).to be_nil
    end

    it "falls back to the SiteSetting per-agent-type family defaults" do
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(Ai::AgentToolBridgeService::FAMILY_DEFAULTS_SETTING)
                                          .and_return({ "monitor" => %w[list_skills] })

      actions = mcp_actions(described_class.for(agent_with(agent_type: "monitor")))

      expect(actions).to match_array(%w[list_skills] | described_class::BOOTSTRAP_ACTIONS)
    end

    # Enumerated, NOT matched against the constant: this is the kill switch's
    # residual surface, so growing BootstrapVerbs must be a reviewed widening of
    # what a DISABLED agent still gets, not a silent one. HIER-P2H took it from
    # three verbs to nine; every one is declared `mutating: false`
    # (bootstrap_verbs_spec) except record_agent_execution, which writes only
    # this run's own history row.
    it "keeps only the bootstrap verbs when platform tools are disabled for the agent" do
      actions = mcp_actions(described_class.for(agent_with(tool_access: { "enabled" => false })))

      expect(actions).to contain_exactly(
        "get_agent", "discover_skills", "get_skill_context", "search_knowledge",
        "query_learnings", "code_semantic_search", "describe_tool", "route_task",
        "record_agent_execution"
      )
      expect(actions).to match_array(described_class::BOOTSTRAP_ACTIONS)
    end
  end

  # The property the brief pins: every emitted MCP name is a registered action,
  # walked over every canonical agent the core seeds define plus one agent per
  # tool_access shape. Names are checked against the registry's own surface
  # (PlatformApiToolRegistry.all_tools keys), never against a literal list.
  describe "every emitted MCP name is a registered action" do
    let!(:admin_account) { create(:account, name: "Powernode Admin") }
    let!(:admin_user)    { create(:user, account: admin_account, email: "admin@powernode.org") }
    let!(:anthropic)     { create(:ai_provider, account: admin_account, provider_type: "anthropic", is_active: true) }
    let!(:openai)        { create(:ai_provider, account: admin_account, provider_type: "openai", is_active: true) }
    let!(:ollama)        { create(:ai_provider, account: admin_account, provider_type: "ollama", is_active: true) }

    def load_seed!(file)
      silence_warnings { load Rails.root.join("db", "seeds", file) }
    end

    it "holds for every canonical (global, is_system) agent the core seeds define" do
      %w[claude_agents_seed.rb monitoring_analytics_agents_seed.rb ai_utility_agents_seed.rb].each { |f| load_seed!(f) }
      canonicals = Ai::Agent.global.where(is_system: true).active.where.not(agent_type: "mcp_client").to_a
      expect(canonicals).not_to be_empty

      registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.to_set
      canonicals.each do |agent|
        tools = described_class.for(agent)
        next if tools.nil? # unscoped: `tools:` omitted

        mcp_actions(tools).each do |action|
          expect(registered).to include(action), "#{agent.slug} emitted unregistered action #{action}"
        end
      end
    end

    it "holds for each tool_access shape" do
      registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.to_set
      shapes = [ nil, { "allowed_tools" => %w[search_knowledge bogus] }, { "tool_families" => %w[docker_list] },
                 { "enabled" => false } ]

      shapes.each do |shape|
        tools = described_class.for(agent_with(tool_access: shape))
        mcp_actions(tools).each do |action|
          expect(registered).to include(action), "shape #{shape.inspect} emitted unregistered action #{action}"
        end
      end
    end
  end
end
