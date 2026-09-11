# frozen_string_literal: true

require "rails_helper"

# Increment E2 — MCP safety annotations come from `declare_action`, not from a
# guess about the action's name.
#
# The audit's finding (docs/operations/vision-alignment-audit-2026-09-10.md,
# remedy 11): 569 of 634 advertised actions carried no safety annotation at
# all, `destructiveHint` appeared nowhere in the codebase, and — the sharp end
# — three DECLARED-MUTATING actions were advertised `readOnlyHint: true`
# because `perceive` and `measure` sit in the name-prefix list. Ground truth
# existed for every one of them the whole time.
#
# Every example below drives the catalog through a FAKE tool class registered
# into the real registry map, so the oracle is the catalog's behaviour and not
# some particular production verb's current declaration. The three real
# `Ai::Tools::CoordinationTool` verbs get their own example at the end,
# because that one is a regression pin on a named defect.
RSpec.describe Mcp::ToolCatalog, "safety annotations" do
  # THE FAKES ARE ANONYMOUS CLASSES BOUND WITH stub_const, NOT `class Foo` in
  # the describe block. Two reasons, both load-bearing here:
  #
  #   * `class Foo` inside a block defines a TOP-LEVEL constant, not one under
  #     the described class, so a registry map naming
  #     "Mcp::ToolCatalog::FakeReadTool" would resolve to nil and every example
  #     would quietly take the INFERRED path — passing or failing for a reason
  #     that has nothing to do with the catalog;
  #   * a top-level constant defined by a spec file leaks into every other file
  #     in the same process and can clobber an autoloaded class of the same
  #     name. stub_const unwinds after the example.
  def fake_tool(action, **declaration)
    Class.new(::Ai::Tools::BaseTool) do
      const_set(:REQUIRED_PERMISSION, nil)
      declare_action action, **declaration

      define_singleton_method(:definition) do
        { name: action, description: "A fake tool for the annotation oracle.", parameters: {} }
      end
    end
  end

  # A declared read.
  let(:read_tool) { fake_tool("fake_noun_lookup", mutating: false) }
  # A declared write that is not a destroy.
  let(:write_tool) { fake_tool("fake_noun_upsert", mutating: true) }
  # A declared destroy.
  let(:destructive_tool) { fake_tool("fake_noun_obliterate", mutating: true, destructive: true) }
  # A declared write whose NAME leads with a read-only prefix — the shape that
  # was advertised as a safe read before E2.
  let(:measuring_write_tool) { fake_tool("measure_fake_pressure", mutating: true) }
  # A declared write whose name is destroy-SHAPED but which declares nothing
  # about destructiveness. The whole-surface lint forbids this declaration; the
  # catalog no longer papers over it.
  let(:undeclared_destroy_tool) { fake_tool("fake_terminate_instance", mutating: true) }

  let(:catalog) { described_class.new(protocol_version: "2025-11-25") }

  # Binds each fake under a spec-only constant name and registers it in the
  # real registry map, so #declaration_for resolves it exactly as it resolves a
  # production verb — through constantize, the alias hop and .declared_action.
  def with_registry(map)
    named = map.each_with_object({}) do |(action, klass), acc|
      const_name = "E2AnnotationSpec::#{action.split('_').map(&:capitalize).join}Tool"
      stub_const(const_name, klass)
      acc[action] = const_name
    end

    allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools)
      .and_return(::Ai::Tools::PlatformApiToolRegistry::TOOLS.merge(named))
    allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
      named.keys.map { |name| { name: name, description: "d", parameters: {} } }
    )
    stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS", [])
  end

  def annotations_for(name)
    catalog.list_entries.find { |t| t["name"] == "platform.#{name}" }&.dig("annotations")
  end

  describe "a declared read" do
    it "is readOnlyHint true, sourced from the declaration, with no destructiveHint" do
      with_registry("fake_noun_lookup" => read_tool)

      expect(annotations_for("fake_noun_lookup")).to eq(
        "readOnlyHint" => true, "annotationSource" => "declared"
      )
    end

    # The 194-action half of the audit's finding: a read whose name leads with
    # a noun got NO hint at all under the prefix rule.
    it "is annotated even though its name matches no read-only prefix" do
      with_registry("fake_noun_lookup" => read_tool)

      expect(catalog.send(:read_only_action?, "fake_noun_lookup")).to be(false)
      expect(annotations_for("fake_noun_lookup")["readOnlyHint"]).to be(true)
    end
  end

  describe "a declared write" do
    it "is readOnlyHint false with an explicit destructiveHint false" do
      with_registry("fake_noun_upsert" => write_tool)

      expect(annotations_for("fake_noun_upsert")).to eq(
        "readOnlyHint" => false, "destructiveHint" => false, "annotationSource" => "declared"
      )
    end

    # THE WRONG-HINT ARM. Both `measure` and `perceive` are in
    # READ_ONLY_ACTION_PREFIXES, so the pre-E2 catalog called this a safe read.
    it "loses readOnlyHint even when its name leads with a read-only prefix" do
      with_registry("measure_fake_pressure" => measuring_write_tool)

      # The heuristic still says "read" — asserted, so the example proves the
      # DECLARATION overrode it rather than the heuristic happening to agree.
      expect(catalog.send(:read_only_action?, "measure_fake_pressure")).to be(true)
      expect(annotations_for("measure_fake_pressure")["readOnlyHint"]).to be(false)
    end
  end

  describe "a declared destroy" do
    it "is destructiveHint true and still a write" do
      with_registry("fake_noun_obliterate" => destructive_tool)

      expect(annotations_for("fake_noun_obliterate")).to eq(
        "readOnlyHint" => false, "destructiveHint" => true, "annotationSource" => "declared"
      )
    end
  end

  describe "an undeclared action" do
    it "falls back to the prefix rule and reports the source as inferred" do
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS",
                 [ { id: "platform.health", description: "Health.", input_schema: { "type" => "object" } } ])
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([])

      entry = catalog.list_entries.find { |t| t["name"] == "platform.health" }

      expect(entry["annotations"]).to eq("readOnlyHint" => true, "annotationSource" => "inferred")
    end

    # The gap made VISIBLE. Before E2 an action with no ground truth and an
    # action declared "write" both rendered as "no annotations", so a reader
    # could not tell "we know it writes" from "we have no idea".
    it "still reports its source when the prefix rule says nothing" do
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS",
                 [ { id: "platform.cost_analysis", description: "Costs.", input_schema: { "type" => "object" } } ])
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([])

      entry = catalog.list_entries.find { |t| t["name"] == "platform.cost_analysis" }

      expect(entry["annotations"]).to eq("annotationSource" => "inferred")
      expect(entry["annotations"]).not_to have_key("readOnlyHint")
    end
  end

  # THE DECLARATION ALONE DECIDES A DECLARED WRITE (E2 follow-through). While
  # the system extension's destroy-shaped verbs were undeclared, a floor here
  # published destructiveHint true for any overlay match. Every such verb is
  # declared now, so the floor is gone and the catalog reports exactly what the
  # declaration says. Agreement with the overlay is enforced in one place, by
  # spec/lint/destructive_declaration_matches_deny_overlay_spec.rb, over the
  # whole surface.
  describe "a declared write" do
    # The overlay is NOT consulted on this path: a destroy-shaped name that
    # declares nothing publishes false. That declaration cannot exist in the
    # tree — the lint refuses it — which is why the floor could go.
    it "publishes exactly its declaration, even for a destroy-shaped name that declares nothing" do
      with_registry("fake_terminate_instance" => undeclared_destroy_tool)

      expect(::Mcp::Principal.destructive_tool?("fake_terminate_instance")).to be(true)
      expect(annotations_for("fake_terminate_instance")["destructiveHint"]).to be(false)
    end

    it "leaves an ordinary write false" do
      with_registry("fake_noun_upsert" => write_tool)

      expect(::Mcp::Principal.destructive_tool?("fake_noun_upsert")).to be(false)
      expect(annotations_for("fake_noun_upsert")["destructiveHint"]).to be(false)
    end

    # A declared destroy is true whether or not the glob matches its name.
    it "publishes a declared destroy true whatever the overlay says" do
      with_registry("fake_noun_obliterate" => destructive_tool)

      expect(::Mcp::Principal.destructive_tool?("fake_noun_obliterate")).to be(false)
      expect(annotations_for("fake_noun_obliterate")["destructiveHint"]).to be(true)
    end

    # THE GENUINELY UNDECLARED ARM (E2 review L4). The first example in this
    # group names a class that DOES declare — mutating, just not destructive —
    # so it takes the declared path. An action with no declaration at all
    # takes the inferred path, where the overlay is still the only input. Its
    # other arm is "still reports its source when the prefix rule says
    # nothing" above: a non-destroy-shaped inferred action still carries
    # annotationSource alone.
    it "reports destructiveHint true for a destroy-shaped action with no declaration at all" do
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS",
                 [ { id: "platform.purge_fake_cache", description: "Purges.", input_schema: { "type" => "object" } } ])
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([])

      entry = catalog.list_entries.find { |t| t["name"] == "platform.purge_fake_cache" }

      expect(::Mcp::Principal.destructive_tool?("purge_fake_cache")).to be(true)
      expect(entry["annotations"]).to eq(
        "readOnlyHint" => false, "destructiveHint" => true, "annotationSource" => "inferred"
      )
    end
  end

  describe "version gating" do
    it "emits no annotations at all for a client predating 2025-03-26" do
      with_registry("fake_noun_lookup" => read_tool)
      old = described_class.new(protocol_version: "2024-11-05")

      entry = old.list_entries.find { |t| t["name"] == "platform.fake_noun_lookup" }

      expect(entry).not_to have_key("annotations")
    end
  end

  # REGRESSION PIN on the audit's named defect. Not a fake: these three verbs
  # are the ones that were actually advertised as safe reads, they all require
  # ai.manage, and the file's own comments place them on the write side.
  describe "Ai::Tools::CoordinationTool's three measure/perceive writes" do
    let(:full_catalog) { described_class.new(protocol_version: "2025-11-25") }

    %w[measure_pressure perceive_pressure perceive_signals].each do |action|
      it "#{action} is not advertised read-only" do
        entry = full_catalog.list_entries.find { |t| t["name"] == "platform.#{action}" }

        expect(entry).not_to be_nil, "#{action} is no longer advertised; this pin needs revisiting"
        # Both halves: the heuristic still calls it a read, and the catalog
        # no longer does.
        expect(full_catalog.send(:read_only_action?, action)).to be(true)
        expect(entry["annotations"]["readOnlyHint"]).to be(false)
        expect(entry["annotations"]["annotationSource"]).to eq("declared")
      end
    end
  end

  # The alias hop. `code_prune_stale` is advertised under that registry key but
  # BaseTool#execute dispatches it as `prune_stale`, so a declaration lookup
  # keyed on the registry key finds nothing and silently drops a destroy-shaped
  # verb onto the inferred path.
  describe "an aliased registry key" do
    it "resolves the declaration through the alias and reports it as declared" do
      full = described_class.new(protocol_version: "2025-11-25")
      entry = full.list_entries.find { |t| t["name"] == "platform.code_prune_stale" }

      expect(::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES["code_prune_stale"]).to eq("prune_stale")
      expect(entry["annotations"]["annotationSource"]).to eq("declared")
      expect(entry["annotations"]["destructiveHint"]).to be(true)
    end
  end
end
