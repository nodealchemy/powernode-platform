# frozen_string_literal: true

require "rails_helper"

# COVERAGE RATCHET (IMP-a0553dda1ec3).
#
# Ai::Tools::BaseTool.declare_action is the governance registry the fail-closed
# flip (IMP-439d31353f9b) will act on: "an undeclared action is refused". One
# action is declared platform-wide today, so the flip cannot be made until the
# tail is measured and bounded. This spec bounds it.
#
# It does NOT declare anything and does NOT change any gate. It asserts a
# two-way correspondence between the live registry and a CHECKED-IN snapshot so
# a reviewer sees the ungoverned surface move as a diff:
#
#   growth  a registry action that is neither declared nor already listed
#           fails -> the surface cannot grow silently.
#   rot     a listed action that HAS since been declared (or whose key is gone)
#           fails -> the snapshot cannot become a permanent exemption list.
#
# The computation lives in spec/support/tool_declaration_coverage.rb; the two
# synthetic examples below drive it with fabricated registries so the oracle is
# proven RED in both directions from inside the suite, not merely observed
# green against a tree that already agrees.
#
# KNOWN BOUND: the walk is PlatformApiToolRegistry.all_tools, i.e. core TOOLS
# plus whatever extension maps are registered in THIS environment. An
# environment that loads an extension tool map absent here will see its actions
# as growth — which is the ratchet working, and is resolved by a reviewed
# snapshot addition, not by loosening the check.
RSpec.describe "MCP action declaration coverage ratchet" do
  subject(:report) { ToolDeclarationCoverage.report }

  it "resolves every registry key to the action name BaseTool#execute dispatches on" do
    # Guards the crux: a ratchet keyed on the raw registry key would read every
    # ACTION_ALIASES entry as undeclared. ACTION_ALIASES only applies when the
    # tool is action-dispatched, so assert against the registrar's own predicate.
    registrar = Ai::Tools::McpPlatformToolRegistrar
    aliased_key, aliased_action = registrar::ACTION_ALIASES.first
    tool_class = Ai::Tools::PlatformApiToolRegistry.all_tools.fetch(aliased_key).constantize

    expect(registrar.send(:action_dispatched?, tool_class)).to be(true)
    expect(ToolDeclarationCoverage.resolved_action_name(aliased_key, tool_class)).to eq(aliased_action)
    expect(report[:undeclared] + report[:declared]).to include(aliased_action)
    expect(report[:undeclared] + report[:declared]).not_to include(aliased_key)
  end

  it "has no ungoverned growth: every registry action is declared or already in the frozen snapshot" do
    expect(report[:ungoverned_growth]).to be_empty, lambda {
      "#{report[:ungoverned_growth].size} registry action(s) are undeclared and NOT in the frozen " \
      "snapshot (#{ToolDeclarationCoverage::SNAPSHOT_PATH}):\n  " +
        report[:ungoverned_growth].join("\n  ") +
        "\n\nDeclare them with Ai::Tools::BaseTool.declare_action, or make growing the " \
        "ungoverned surface an explicit reviewed decision by adding them to the snapshot."
    }
  end

  it "has no stale snapshot entries: nothing listed is declared or de-registered" do
    expect(report[:stale_snapshot_entries]).to be_empty, lambda {
      "#{report[:stale_snapshot_entries].size} snapshot entr(y/ies) are no longer undeclared " \
      "registry actions — they were declared, or their registry key is gone:\n  " +
        report[:stale_snapshot_entries].join("\n  ") +
        "\n\nDelete them from #{ToolDeclarationCoverage::SNAPSHOT_PATH}. The snapshot may only shrink."
    }
  end

  it "accounts for the whole registry surface" do
    expect(report[:declared].size + report[:undeclared].size).to eq(report[:resolved_actions])
    expect(report[:registry_keys]).to be >= report[:resolved_actions]
    expect(report[:declared]).not_to be_empty
  end

  describe "the oracle is genuinely red in both directions" do
    let(:real_map) { Ai::Tools::PlatformApiToolRegistry.all_tools }
    let(:snapshot) { ToolDeclarationCoverage.snapshot_entries }

    # An action-dispatched tool with no declarations — the shape a genuinely new
    # ungoverned action arrives in. Anonymous + stub_const so the fixture cannot
    # be mistaken for real surface and nothing is added to the real registry.
    before do
      stub_const("ZzRatchetFixtureTool", Class.new(Ai::Tools::BaseTool) do
        def self.definition
          {
            name: "zz_ratchet_fixture_tool",
            description: "ratchet mutation fixture",
            parameters: { action: { type: "string", required: true } }
          }
        end
      end)
    end

    it "fails when a NEW undeclared registry key appears (growth)" do
      grown = real_map.merge("zz_ratchet_fixture_ungoverned" => "ZzRatchetFixtureTool")
      grown_report = ToolDeclarationCoverage.report(grown, snapshot)

      expect(grown_report[:ungoverned_growth]).to include("zz_ratchet_fixture_ungoverned")
    end

    it "fails when an extension registers an undeclared tool through the generic seam" do
      # The extension arm is not inert: all_tools merges extension_tools, so a
      # map plugged in via .register_extension_tools lands in the same walk.
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:extension_tools)
        .and_return("zz_ratchet_fixture_extension_action" => "ZzRatchetFixtureTool")

      expect(ToolDeclarationCoverage.report[:ungoverned_growth])
        .to include("zz_ratchet_fixture_extension_action")
    end

    it "fails when a snapshot entry has since been declared (rot)" do
      stale = snapshot + report[:declared]
      stale_report = ToolDeclarationCoverage.report(real_map, stale)

      expect(stale_report[:stale_snapshot_entries]).to include(*report[:declared])
    end

    it "fails when a snapshot entry names an action the registry no longer has (rot)" do
      stale = snapshot + ["zz_ratchet_fixture_deregistered"]
      stale_report = ToolDeclarationCoverage.report(real_map, stale)

      expect(stale_report[:stale_snapshot_entries]).to include("zz_ratchet_fixture_deregistered")
    end
  end

  describe "declaration lookup" do
    it "walks the ancestry so an inherited declaration is not read as undeclared" do
      parent = Class.new(Ai::Tools::BaseTool) do
        declare_action "zz_ratchet_fixture_inherited", mutating: false
      end
      child = Class.new(parent)
      stub_const("ZzRatchetFixtureChildTool", child)

      expect(child.declared_actions).to be_empty
      expect(
        ToolDeclarationCoverage.declared?("zz_ratchet_fixture_inherited", ["ZzRatchetFixtureChildTool"])
      ).to be(true)
    end
  end
end
