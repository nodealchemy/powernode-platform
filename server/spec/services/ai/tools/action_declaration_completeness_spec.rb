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
# NON-ENFORCING, deliberately, for the actions APO-1a declared. A declaration
# reaches Ai::AutonomyGate only when BaseTool#gated_action? is true, which needs
# mutating + action_category + executor_class + gate_context + on_proceed all
# present; the declarations added by that increment carry `mutating:` alone, so
# #execute takes the same `return call(params)` path an undeclared action took
# and every per-action permission check inside #call still runs.
#
# GATE-ROUTED is therefore an ALLOWLIST, not a count, and the last example pins
# it by name (GATE_ROUTED_ACTIONS below). Arming an action is a governance
# decision — it needs a seeded Ai::InterventionPolicy category and an executor
# the gate can replay — so it must be a deliberate edit here rather than a
# number someone bumps. Wiring the rest is APO-1e.
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

  # The actions whose declarations carry the full quartet, i.e. the ones
  # BaseTool#execute routes through Ai::AutonomyGate instead of #call. Each
  # entry names the increment that armed it and the category it parks under, so
  # adding one is a review of the pair rather than a list edit:
  #
  #   system_terminate_instance     IMP-d410a587d6bf  system.task.terminate
  #   system_create_instance_pool   IMP-067f39468350  system.instance_pool_create
  #   system_update_instance_pool   IMP-067f39468350  system.instance_pool_ceiling_raise
  #                                                   / system.instance_pool_archive
  #   system_set_service_backends   IMP-0c10b9fd5596  system.service_backends_update
  #   system_delete_volume_snapshot IMP-e025722ef14e  system.volume_snapshot_delete
  #   system_gitops_apply_proposal  IMP-0b4f18ae4384  system.gitops_apply_proposal
  #   system_cordon_instance        IMP-0467eee9fc57  system.instance_cordon
  #   system_uncordon_instance      IMP-0467eee9fc57  system.instance_cordon
  #   system_gitops_register_repository SWEEP-2026-09-03 system.gitops_register_repository
  #   set_delegation_policy         HIER-P0           ai.delegation_policy.update
  #                                 (core category; an agent PROPOSES its own
  #                                 delegation authority, an operator grants it)
  #
  # The two pool verbs are the MCP twins of the REST routes IMP-24daa05e7a22
  # gated: while they were declared `mutating:` only, an agent could raise the
  # spend ceiling the ungated 60 s replenish tick spends up to — or mint a pool
  # whose ceiling nobody approved — by naming the MCP door instead of the REST
  # one. They replay through Ai::Executors::DeferredToolCall, so the action
  # body stays the only writer on both branches.
  GATE_ROUTED_ACTIONS = %w[
    system_terminate_instance
    system_create_instance_pool
    system_update_instance_pool
    system_replace_instance
    system_reap_instance
    system_set_service_backends
    system_delete_volume_snapshot
    system_gitops_apply_proposal
    system_cordon_instance
    system_uncordon_instance
    system_gitops_register_repository
    set_delegation_policy
  ].freeze

  it "arms the gate on exactly the actions that are meant to be gate-routed" do
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

    expect(gate_routed).to match_array(GATE_ROUTED_ACTIONS), <<~MSG
      The set of gate-routed MCP actions changed.

      Arming one is a governance decision, not a refactor: BaseTool#execute
      stops calling #call for it, so its action_category must be a category
      Ai::InterventionPolicyService actually resolves (an unmatched one
      defaults to require_approval) and its executor_class must be one the
      gate can replay. Disarming one silently returns a mutation to the
      ungated path. Either way, add or remove it in GATE_ROUTED_ACTIONS above
      WITH its increment and category, in the same change.
    MSG
  end

  # THE ROUTING PRECONDITION of the equality above (IMP-149b35e5f16f).
  #
  # A declare_action row governs an action only if BaseTool#execute is what
  # actually runs it — that is where the lookup, the instance deny overlay and
  # #validate_params! live. A tool that defines its own #execute satisfies the
  # set equality while governing nothing, and the equality cannot see it.
  # Ai::Tools::FederationTool was exactly that tool, and it is the one that
  # proxies arbitrary REMOTE tool names; APO-1e cannot read this file as
  # coverage while any such override exists.
  #
  # Stated POSITIVELY over every registry-backed class rather than as a pin on
  # the one known offender: a pin goes green by deletion and says nothing about
  # the next override someone adds.
  it "serves every advertised action through BaseTool#execute — no class overrides the chokepoint" do
    # No SKIPS. A class that will not resolve, and an #execute the walk cannot
    # introspect, are reported as offenders rather than filtered away: a guard
    # stated as a positive completeness assertion must not have quiet escapes.
    # `instance_method`, not `method_defined?`, so a PRIVATE or protected
    # override is flagged too instead of reading as "no override".
    overrides = registry_map.values.uniq.sort.filter_map do |class_name|
      klass = class_name.safe_constantize
      next "#{class_name} (does not resolve to a class)" unless klass.is_a?(Module)

      begin
        owner = klass.instance_method(:execute).owner
      rescue NameError
        next "#{class_name} (defines no #execute at all)"
      end

      "#{class_name} (#execute owned by #{owner})" unless owner == Ai::Tools::BaseTool
    end

    expect(overrides).to be_empty, lambda {
      "#{overrides.size} registry-backed tool class(es) do not serve #execute from " \
      "Ai::Tools::BaseTool, so their declarations are counted by the equality above " \
      "but govern nothing:\n  " +
        overrides.join("\n  ") +
        "\n\nMove the dispatch body into #call so BaseTool#execute runs the declaration lookup, " \
        "the instance deny overlay and #validate_params! first."
    }
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
