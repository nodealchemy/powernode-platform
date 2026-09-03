# frozen_string_literal: true

require "rails_helper"

# HIER-P2H — THE ONE bootstrap allowlist: the read-only platform verbs every
# agent needs in order to obey Ai::Agent::BASE_GUARDRAILS (query platform
# guidance, discover skills, fetch its own skill context, look a tool up,
# route a task), whichever tool_families scope it is served under.
#
# THE FINDING (P2D). Ai::AgentToolBridgeService#scope_to_tool_families was a
# plain family select: any agent with a configured tool_families list lost
# discover_skills / get_skill_context / search_knowledge / query_learnings /
# describe_tool / route_task at run time while BASE_GUARDRAILS — prepended to
# its every prompt — ordered it to call them. The Ingress seed listed them per
# agent as a workaround; the sibling wave-2 seeds did not. The exporter's
# Ai::ClaudeExport::ToolAllowlist carried its own, smaller BOOTSTRAP_ACTIONS,
# so Claude Code and the platform disagreed about what an agent always has.
#
# Read-only is asserted through the declaration under the name that actually
# dispatches (McpPlatformToolRegistrar::ACTION_ALIASES), never by inspection
# of the name: an entry the registry does not advertise, or one declared
# mutating, fails here — so a verb cannot be added to the set that every
# agent receives without that being a deliberate, reviewed change.
RSpec.describe Ai::Tools::BootstrapVerbs do
  let(:registry_map) { Ai::Tools::PlatformApiToolRegistry.all_tools }

  def declaration_for(name)
    class_name = registry_map[name]
    return nil unless class_name

    dispatched = Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(name, name)
    class_name.constantize.declared_action(dispatched)
  end

  it "names the verbs BASE_GUARDRAILS tells every agent to call" do
    expect(described_class::ACTIONS).to include(
      "discover_skills", "get_skill_context", "search_knowledge", "query_learnings",
      "describe_tool", "route_task"
    )
  end

  it "keeps the exporter's original bootstrap verb, so a Claude Code skeleton can still fetch its own prompt" do
    expect(described_class::ACTIONS).to include("get_agent")
  end

  it "is frozen and duplicate-free" do
    expect(described_class::ACTIONS).to be_frozen
    expect(described_class::ACTIONS.uniq).to eq(described_class::ACTIONS)
  end

  it "contains only registered actions" do
    unregistered = described_class::ACTIONS.reject { |name| registry_map.key?(name) }
    expect(unregistered).to be_empty, "bootstrap verbs not in PlatformApiToolRegistry.all_tools: #{unregistered.inspect}"
  end

  # The load-bearing property: nothing in this set writes. Asserted via the
  # declaration (`mutating: false`) of every entry, resolved through the
  # dispatch alias — an undeclared entry counts as mutating, conservatively.
  it "contains no mutating verb — every entry is declared mutating: false under its dispatched name" do
    offenders = described_class::ACTIONS.filter_map do |name|
      declaration = declaration_for(name)
      "#{name} (#{declaration.nil? ? 'undeclared' : "mutating: #{declaration[:mutating].inspect}"})" unless declaration && declaration[:mutating] == false
    end

    expect(offenders).to be_empty, "bootstrap verbs that are not read-only: #{offenders.inspect}"
  end

  # Derived, not restated: every REGISTERED action BASE_GUARDRAILS names by
  # its registry key must be in the set, so a guardrail that starts telling
  # agents to call a new verb reds here until the set carries it.
  it "covers every registered action BASE_GUARDRAILS names" do
    named = Ai::Agent::BASE_GUARDRAILS.scan(/[a-z][a-z0-9_]+/).uniq.select { |token| registry_map.key?(token) }

    expect(named).not_to be_empty
    expect(described_class::ACTIONS).to include(*named)
  end

  describe ".include?" do
    it "answers by registry name, accepting symbols" do
      expect(described_class.include?(:search_knowledge)).to be(true)
      expect(described_class.include?("delete_agent")).to be(false)
    end
  end

  # ONE constant, three consumers. The exporter unions the same set (plus its
  # self-report verb, which is a write and so cannot live in the read-only
  # set) so Claude Code and the platform agree on what an agent always has.
  it "is the set Ai::ClaudeExport::ToolAllowlist unions into every skeleton" do
    expect(Ai::ClaudeExport::ToolAllowlist::BOOTSTRAP_ACTIONS).to include(*described_class::ACTIONS)
    expect(Ai::ClaudeExport::ToolAllowlist::BOOTSTRAP_ACTIONS - described_class::ACTIONS)
      .to eq(Ai::ClaudeExport::ToolAllowlist::SELF_REPORT_ACTIONS)
  end
end
