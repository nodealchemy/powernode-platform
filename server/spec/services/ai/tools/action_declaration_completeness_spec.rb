# frozen_string_literal: true

require "rails_helper"

# APO-1a (IMP-1e58753b3b6c) — COMPLETENESS of the governance registry.
#
# The sibling ratchet (declaration_coverage_ratchet_spec.rb) bounds the
# UNGOVERNED surface against a frozen snapshot: it stops the tail from growing.
# This file asserts the tail is GONE, and it does so with set EQUALITY rather
# than an existence check, in BOTH directions:
#
#   advertised - declared   an MCP action that executes with no
#                           Ai::Tools::BaseTool.declare_action record. This is
#                           the direction an existence check can also see.
#   declared - advertised   a declaration whose NAME matches nothing the
#                           registry advertises — a typo, a renamed action, or
#                           a declaration keyed on the registry key when
#                           BaseTool#execute looks it up by the ALIASED name.
#                           An existence check is blind to this: the action
#                           still runs undeclared while the declaration sits
#                           there looking like coverage.
#
# NON-ENFORCING, deliberately. This increment records intent only. A
# declaration reaches Ai::AutonomyGate only when BaseTool#gated_action? is true,
# which needs mutating + action_category + executor_class + gate_context +
# on_proceed all present; the declarations added here carry `mutating:` alone,
# so #execute takes the same `return call(params)` path an undeclared action
# took and every per-action permission check inside #call still runs. The last
# example pins that: exactly one action on the platform is gate-routed today.
# Flipping fail-closed, and wiring executors for the rest, is APO-1e.
#
# KNOWN BOUND: the walk is PlatformApiToolRegistry.all_tools, i.e. core TOOLS
# plus whatever extension maps are registered in THIS environment. An
# environment that loads an extension tool map absent here (a maintainer bundle
# with a private extension calling .register_extension_tools, say) sees its
# actions as gaps. This file takes NO snapshot input, and the sibling ratchet's
# snapshot is now empty, so the remedy is to DECLARE that extension's actions
# rather than to acknowledge them.
RSpec.describe "MCP action declaration completeness" do
  # action name (as BaseTool#execute resolves it) => tool class names serving it
  def resolved_for(map)
    ToolDeclarationCoverage.resolved_actions(map)
  end

  # GAP direction, computed PER SERVING CLASS. BaseTool#execute resolves the
  # declaration on the class actually serving the action, so a union over every
  # registry-backed class would let a declaration on the WRONG tool close the
  # gap. ToolDeclarationCoverage.declared? is the per-class form (and is what
  # the sibling ratchet uses), so both oracles agree on what "declared" means.
  def undeclared_for(map)
    resolved_for(map)
      .reject { |action, class_names| ToolDeclarationCoverage.declared?(action, class_names) }
      .keys.to_set
  end

  # PHANTOM direction. A union is correct here and only here: a declaration
  # naming nothing the registry advertises is a phantom whichever class holds
  # it. Walks the same ancestry BaseTool.declared_action walks so an inherited
  # declaration counts.
  def declared_for(map)
    map.values.uniq.each_with_object(Set.new) do |class_name, acc|
      klass = class_name.safe_constantize
      while klass.respond_to?(:declared_actions)
        acc.merge(klass.declared_actions.keys)
        klass = klass.superclass
      end
    end
  end

  let(:registry_map) { Ai::Tools::PlatformApiToolRegistry.all_tools }
  let(:advertised)   { resolved_for(registry_map).keys.to_set }
  let(:declared)     { declared_for(registry_map) }

  it "declares exactly the advertised action set — no gaps" do
    missing = undeclared_for(registry_map).to_a.sort

    expect(missing).to be_empty, lambda {
      "#{missing.size} advertised MCP action(s) execute with NO governance declaration:\n  " +
        missing.join("\n  ") +
        "\n\nDeclare each with Ai::Tools::BaseTool.declare_action(name, mutating:) in its tool class."
    }
  end

  it "declares exactly the advertised action set — no phantom declarations" do
    extra = (declared - advertised).to_a.sort

    expect(extra).to be_empty, lambda {
      "#{extra.size} declaration(s) name something the registry does not advertise " \
      "(typo, rename, or keyed on the registry key instead of the resolved action name):\n  " +
        extra.join("\n  ")
    }
  end

  it "is a set EQUALITY, not a containment" do
    # The union-level statement of the same pair. It is the WEAKER half — the
    # gap example above is the per-serving-class form — and is kept because a
    # containment check in either direction alone is what this oracle exists to
    # rule out.
    expect(declared).to eq(advertised)
  end

  it "is not vacuous: the advertised surface is the whole platform catalog" do
    expect(advertised.size).to be > 500
    expect(declared.size).to be > 500
  end

  it "leaves every newly declared action NON-ENFORCING" do
    # Uses BaseTool's own predicate rather than restating its four conditions,
    # so this cannot drift from the routing decision #execute actually makes.
    probe = Ai::Tools::BaseTool.new(account: nil)

    # EVERY serving class, not class_names.first: an action served by two
    # classes is gate-routed if either of them arms it.
    gate_routed = resolved_for(registry_map).filter_map do |action, class_names|
      armed = class_names.any? do |class_name|
        declaration = class_name.safe_constantize&.declared_action(action)
        declaration && probe.send(:gated_action?, declaration)
      end
      action if armed
    end

    expect(gate_routed).to contain_exactly("system_terminate_instance")
  end

  # KNOWN-INERT DECLARATION — the equality cannot see this, so it is pinned
  # here. Ai::Tools::FederationTool overrides #execute and never calls super
  # (the same exemption base_tool.rb records), so BaseTool#execute's declaration
  # lookup never runs for it: its two rows satisfy the equality above while
  # governing nothing. APO-1e must close the override before it can read the
  # equality as coverage for the tool that proxies arbitrary REMOTE tool names.
  it "pins FederationTool as a declaration the equality counts but cannot govern" do
    expect(Ai::Tools::FederationTool.instance_method(:execute).owner)
      .to eq(Ai::Tools::FederationTool)

    source = File.read(Rails.root.join("app/services/ai/tools/federation_tool.rb"))
    start  = source.index("      def execute(params:)")
    finish = source.index("\n      private", start.to_i)
    expect(start).to be_present, "FederationTool#execute moved; re-establish this region"
    expect(finish).to be_present, "FederationTool#execute region has no trailing `private`"

    expect(source[start...finish]).not_to include("super")
  end

  describe "the oracle is genuinely red in both directions" do
    before do
      stub_const("ZzCompletenessFixtureTool", Class.new(Ai::Tools::BaseTool) do
        def self.definition
          {
            name: "zz_completeness_fixture_tool",
            description: "completeness mutation fixture",
            parameters: { action: { type: "string", required: true } }
          }
        end
      end)
    end

    it "reports a gap when an advertised action carries no declaration" do
      grown = registry_map.merge("zz_completeness_fixture_undeclared" => "ZzCompletenessFixtureTool")

      expect(undeclared_for(grown)).to include("zz_completeness_fixture_undeclared")
    end

    it "reports a phantom when a class declares a name the registry never advertises" do
      ZzCompletenessFixtureTool.declare_action "zz_completeness_fixture_phantom", mutating: false
      grown = registry_map.merge("zz_completeness_fixture_real" => "ZzCompletenessFixtureTool")

      expect(declared_for(grown) - resolved_for(grown).keys.to_set)
        .to include("zz_completeness_fixture_phantom")
    end
  end
end
