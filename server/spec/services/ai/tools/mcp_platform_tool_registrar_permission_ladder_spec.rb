# frozen_string_literal: true

require "rails_helper"

# IMP-bab07f770c0e — the `mcp_tools` rows the registrar writes must state the
# permission that ACTUALLY gates each action, not its tool class's floor.
#
# Ai::Tools::McpPlatformToolRegistrar#sync_to_database! used to compute the
# stored value as
#
#     required_permission = tool_class::REQUIRED_PERMISSION rescue nil
#
# once per registry ACTION, which is the CLASS-LEVEL floor. Dispatch resolves
# the per-action ladder first (`ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION`
# — see Ai::Tools::SystemFleetTool#required_perm_for and its 25 siblings), so
# every laddered verb stored a permission strictly lower than its real bar.
#
# This is the same defect b07585402 fixed in the generated markdown catalog, one
# surface over. It is NOT a privilege escalation — Mcp::PermissionValidator runs
# BEFORE the tool's own per-action check and the composition fails closed, so a
# weaker stored value never admits a call the tool would refuse. What it does is
# make the pre-flight verdict UNDERSTATE: the validator says "authorized" for a
# verb the tool then refuses, so the refusal arrives from a gate the validator
# reported wasn't there; and protocol_service.rb#tool_visible_to? over-advertises
# on the same value. Those two are the WHOLE consumer set — the frontend MCP
# browser is NOT one, contrary to the reasoning inherited from the catalog fix:
# Api::V1::McpToolsController#serialize_mcp_tool never emits the column and no
# MCP type under frontend/src carries it. A privilege understatement is still the
# direction that makes a dangerous verb look safe.
#
# THE RATCHET IS AN EQUALITY OVER THE WHOLE MAPPING, not a spot check. An
# existence check cannot see an omission, and an omitted class is exactly the
# failure shape here: b07585402's first cut fixed 333 of 337 and left four verbs
# at the floor, because it looked the ladder up by REGISTRY key while a ladder is
# keyed on the action that RUNS. See #dispatched_action_for.
RSpec.describe Ai::Tools::McpPlatformToolRegistrar, "per-action permission ladder" do
  # Ruby-level memo for the one real sync run — see #stored_permissions.
  singleton_class.attr_accessor :stored_permissions_cache

  let(:account) { create(:account) }
  let!(:mcp_server) { create(:mcp_server, account: account, name: "Powernode MCP") }

  # --- The resolution rule, restated independently of the implementation -----

  # The action the registrar actually DISPATCHES for a registry name. For 25
  # names that is an alias of the key (ACTION_ALIASES, applied in
  # McpPlatformToolRegistrar#execute_tool), and a ladder is keyed on the action
  # that RUNS — the rule stated at code_memory_tool.rb:22-25.
  def self.dispatched_action_for(registry_name)
    ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(registry_name, registry_name)
  end

  # The permission each action REALLY resolves to at dispatch time, computed from
  # the tool classes themselves rather than from the registrar.
  def self.expected_permissions
    @expected_permissions ||= ::Ai::Tools::PlatformApiToolRegistry.all_tools.each_with_object({}) do |(action, class_name), acc|
      klass = class_name.safe_constantize
      next unless klass

      ladder = klass.const_defined?(:ACTION_PERMISSIONS) ? klass::ACTION_PERMISSIONS : {}
      floor  = klass.const_defined?(:REQUIRED_PERMISSION) ? klass::REQUIRED_PERMISSION : nil

      acc[action] = ladder[dispatched_action_for(action)] || floor
    end
  end

  # Actions whose ladder entry DIFFERS from their class floor. These are the only
  # actions that can distinguish a correct writer from the broken one: where the
  # two coincide, both implementations store the same string.
  def self.laddered_above_floor
    @laddered_above_floor ||= ::Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |action, class_name|
      klass = class_name.safe_constantize
      next unless klass&.const_defined?(:ACTION_PERMISSIONS)

      entry = klass::ACTION_PERMISSIONS[dispatched_action_for(action)]
      floor = klass.const_defined?(:REQUIRED_PERMISSION) ? klass::REQUIRED_PERMISSION : nil
      next if entry.nil? || entry == floor

      action
    end
  end

  def expected_permissions = self.class.expected_permissions
  def laddered_above_floor = self.class.laddered_above_floor

  # --- What the registrar actually wrote ------------------------------------

  # Runs the real writer against a real database and reads the rows back, so the
  # oracle is the stored column and not an argument captured off a stubbed
  # private method.
  #
  # Cached across examples in a class ivar. The DB rows roll back with each
  # example's transaction, but the Hash they produced does not, and the sweep is
  # deterministic — so nine examples share ONE real sync instead of nine
  # (~600 upserts each) on a test database other suites are also using.
  let(:stored_permissions) do
    self.class.stored_permissions_cache ||= begin
      described_class.sync_to_database!(account: account)
      mcp_server.reload.mcp_tools.pluck(:name, :required_permissions).to_h
    end
  end

  it "writes a row for every advertised action" do
    registry_actions = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys
    expect(stored_permissions.keys).to include(*registry_actions),
      "sync_to_database! wrote #{stored_permissions.size} rows but did not cover every one of the " \
      "#{registry_actions.size} advertised actions — every assertion below is unreliable until it does"
  end

  it "has a non-trivial number of actions whose real permission is stricter than their class floor" do
    # Guards the oracle itself: were this set empty (or tiny) every assertion
    # below would pass against a writer that stores only floors.
    expect(laddered_above_floor.size).to be > 330
  end

  # RATCHET — equality over the WHOLE mapping. A spot check cannot see an omitted
  # class; an existence check cannot see an omission at all.
  it "stores the ladder entry for EVERY action that has one" do
    mismatches = laddered_above_floor.filter_map do |action|
      stored = Array(stored_permissions[action])
      expected = [ expected_permissions[action] ].compact
      next if stored == expected

      "#{action}: stored #{stored.inspect}, real gate #{expected.inspect}"
    end

    expect(mismatches).to be_empty, <<~MSG
      #{mismatches.size} of #{laddered_above_floor.size} laddered actions store a permission that is not
      the one dispatch enforces. mcp_tools.required_permissions is read by
      Mcp::PermissionValidator (pre-flight verdict) and
      Mcp::ProtocolService#tool_visible_to? (advertisement).

      #{mismatches.first(15).join("\n")}
    MSG
  end

  # The fallback half: an action with no ladder entry must still store its class
  # floor. Without this, a writer that stored [] everywhere for unladdered
  # actions would pass the ratchet above.
  it "stores the class floor for every action with no ladder entry" do
    unladdered = expected_permissions.keys - laddered_above_floor
    expect(unladdered.size).to be > 100

    mismatches = unladdered.filter_map do |action|
      expected = [ expected_permissions[action] ].compact
      next if Array(stored_permissions[action]) == expected

      "#{action}: stored #{Array(stored_permissions[action]).inspect}, floor #{expected.inspect}"
    end

    expect(mismatches).to be_empty, mismatches.first(15).join("\n")
  end

  # SPOT ORACLE, ALIAS ARM — CodeMemoryTool bundles knowledge-graph WRITE and
  # DESTRUCTIVE verbs behind an "ai.agents.read" floor and ladders each one up.
  # Its ladder is keyed on the dispatched action, so these four are invisible to
  # a registry-key lookup: they are the only actions in the registry that
  # distinguish a dispatch-faithful writer from a merely ladder-aware one — the
  # exact four b07585402's first cut left at the floor. Literal expected strings,
  # independent of the resolution rule above.
  %w[code_upsert_node code_create_relation code_prune_stale code_bulk_index].each do |action|
    it "stores #{action} as ai.knowledge_graph.manage despite its ladder being alias-keyed" do
      expect(::Ai::Tools::PlatformApiToolRegistry.all_tools[action]).to eq("Ai::Tools::CodeMemoryTool")
      expect(::Ai::Tools::CodeMemoryTool::REQUIRED_PERMISSION).to eq("ai.agents.read")
      expect(::Ai::Tools::CodeMemoryTool::ACTION_PERMISSIONS[action]).to be_nil,
        "#{action} is now a literal ladder key — this example no longer proves the alias hop is honored"

      expect(Array(stored_permissions[action])).to eq([ "ai.knowledge_graph.manage" ])
    end
  end

  # SPOT ORACLE, FLOOR ARM — a destructive verb whose ladder entry is strictly
  # stricter than SystemFleetTool's floor.
  {
    "system_deploy_platform" => "system.platform.deploy",
    "system_terminate_instance" => "system.instances.control"
  }.each do |action, real_permission|
    it "stores #{action} as #{real_permission}, not the class floor" do
      floor = ::Ai::Tools::SystemFleetTool::REQUIRED_PERMISSION
      expect(::Ai::Tools::PlatformApiToolRegistry.all_tools[action]).to eq("Ai::Tools::SystemFleetTool")
      expect(real_permission).not_to eq(floor),
        "#{action}'s ladder entry no longer differs from the floor — pick another destructive verb, " \
        "this one can no longer distinguish a correct writer from the broken one"

      expect(Array(stored_permissions[action])).to eq([ real_permission ])
    end
  end

  # --- The second write site -------------------------------------------------

  describe ".build_manifest" do
    # An anonymous class, not a named constant: a constant assigned in a spec
    # file lands on Object where another spec file's same-named constant can
    # clobber it.
    let(:laddered_tool_class) do
      Class.new(Ai::Tools::BaseTool) do
        const_set(:REQUIRED_PERMISSION, "fixture.read")
        const_set(:ACTION_PERMISSIONS, { "fixture_verb" => "fixture.manage" }.freeze)

        def self.definition
          { name: "fixture_verb", description: "fixture", parameters: {} }
        end

        def self.action_definitions = {}
      end
    end

    # register_all! publishes ONE manifest per tool CLASS, keyed on
    # definition[:name]. For a class whose name is itself a laddered action the
    # manifest must carry the ladder entry: protocol_service.rb:218 and :464 read
    # this value for the manifest-only path (no McpTool row), so a floor here
    # under-states the same way the DB column did.
    it "publishes the ladder entry when the tool's own name is a laddered action" do
      manifest = described_class.send(:build_manifest, laddered_tool_class)

      expect(manifest["required_permissions"]).to eq([ "fixture.manage" ])
    end

    it "falls back to the class floor when the tool's name is not a laddered action" do
      unladdered = Class.new(Ai::Tools::BaseTool) do
        const_set(:REQUIRED_PERMISSION, "fixture.read")
        const_set(:ACTION_PERMISSIONS, { "some_other_verb" => "fixture.manage" }.freeze)

        def self.definition
          { name: "fixture_umbrella", description: "fixture", parameters: {} }
        end

        def self.action_definitions = {}
      end

      manifest = described_class.send(:build_manifest, unladdered)

      # NOT the union of the ladder. required_permissions is CONJUNCTIVE
      # (Mcp::PermissionValidator#missing_required_permissions subtracts it from
      # the user's set), so publishing every permission a multi-action class can
      # require would deny — and, via #tool_visible_to?, hide — the class from a
      # caller legitimately entitled to its read actions. The floor is the
      # minimum a caller needs to reach the class; the tool's own
      # ACTION_PERMISSIONS check supplies the per-action bar after that.
      expect(manifest["required_permissions"]).to eq([ "fixture.read" ])
    end

    # THE INHERITANCE EXEMPTION, pinned. Both constant lookups in
    # .resolved_permission_for use `const_defined?` WITH inheritance, and that is
    # a deliberate choice, not an accident of the default: a subclass inheriting
    # both the map and #required_perm_for is really gated by the PARENT's ladder,
    # because the constant in that method body resolves lexically to the defining
    # class. Nothing in the live registry exercises it (every registry tool class
    # is a direct Ai::Tools::BaseTool subclass and BaseTool declares no map), so
    # without this fixture flipping either lookup to `const_defined?(..., false)`
    # is a silent survivor and the documented semantics are unpinned.
    it "honors a ladder and floor INHERITED from a parent tool class" do
      parent = Class.new(Ai::Tools::BaseTool) do
        const_set(:REQUIRED_PERMISSION, "fixture.read")
        const_set(:ACTION_PERMISSIONS, { "fixture_verb" => "fixture.manage" }.freeze)
      end
      child = Class.new(parent) do
        def self.definition
          { name: "fixture_verb", description: "fixture", parameters: {} }
        end

        def self.action_definitions = {}
      end

      expect(child.const_defined?(:ACTION_PERMISSIONS, false)).to be(false),
        "the child now declares its own map — this example no longer proves inheritance is honored"

      expect(described_class.resolved_permission_for(child, "fixture_verb")).to eq("fixture.manage")
      expect(described_class.send(:build_manifest, child)["required_permissions"]).to eq([ "fixture.manage" ])
    end

    # THE UMBRELLA CASE, and the reason build_manifest does not just call the
    # per-action resolver. A class that routes on :action serves several
    # differently-priced verbs under ONE manifest, so publishing one verb's
    # ladder entry as the bar for reaching the class would — required_permissions
    # being conjunctive — deny and hide the class from a caller entitled to its
    # read siblings. No live class has an umbrella name that is also one of its
    # ladder keys, so this fixture is the only thing holding the guard down.
    it "publishes the FLOOR for an :action-dispatched class even when its own name is a ladder key" do
      umbrella = Class.new(Ai::Tools::BaseTool) do
        const_set(:REQUIRED_PERMISSION, "fixture.read")
        const_set(:ACTION_PERMISSIONS, { "fixture_umbrella" => "fixture.manage" }.freeze)

        def self.definition
          { name: "fixture_umbrella", description: "fixture", parameters: { action: { type: "string" } } }
        end

        def self.action_definitions
          { "fixture_umbrella" => {}, "fixture_sibling" => {} }
        end
      end

      expect(described_class.send(:action_dispatched?, umbrella)).to be(true),
        "the fixture no longer routes on :action — it cannot prove the umbrella guard"
      expect(described_class.resolved_permission_for(umbrella, "fixture_umbrella")).to eq("fixture.manage"),
        "the per-action resolver no longer ladders this name — the guard below is vacuous"

      expect(described_class.send(:build_manifest, umbrella)["required_permissions"]).to eq([ "fixture.read" ])
    end
  end

  # --- Oracles that do NOT share the implementation's inputs -----------------

  # The equality above derives its expectation from ACTION_PERMISSIONS and
  # ACTION_ALIASES — the same two tables the implementation reads — so on its own
  # it ratchets "sync_to_database! calls the resolver", not "the resolver matches
  # dispatch". These two close that gap from the other side.
  describe "faithfulness to the enforcing code" do
    # The tools' OWN resolver is what actually refuses a call. Comparing against
    # it means a class that overrides #required_perm_for with custom logic — or
    # stops consulting its ladder — breaks this spec instead of silently
    # publishing a permission nothing enforces.
    it "agrees with each tool class's own #required_perm_for" do
      checked = 0
      mismatches = ::Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |action, class_name|
        klass = class_name.safe_constantize
        next unless klass
        next unless klass.private_method_defined?(:required_perm_for) || klass.method_defined?(:required_perm_for)

        dispatched = self.class.dispatched_action_for(action)
        enforced = klass.allocate.send(:required_perm_for, dispatched)
        checked += 1
        next if enforced == described_class.resolved_permission_for(klass, action)

        "#{action} (#{class_name}): tool enforces #{enforced.inspect}, registrar publishes " \
          "#{described_class.resolved_permission_for(klass, action).inspect}"
      end

      expect(checked).to be > 300,
        "only #{checked} actions belong to a class defining #required_perm_for — this oracle has gone " \
        "vacuous; find where per-action enforcement moved to"
      expect(mismatches).to be_empty, mismatches.first(15).join("\n")
    end

    # The one input neither the implementation nor the equality above cross-checks
    # is ACTION_ALIASES itself. A ladder keyed on an internal name whose alias row
    # was never added is DEAD at dispatch: the tool receives the registry key,
    # finds no entry, and enforces the floor — and both the registrar and the
    # equality agree on that floor, so the ratchet stays green over a permission
    # its author believed was in force. Catching it needs a check on the ladder
    # keys themselves.
    it "has no ladder entry that is unreachable at dispatch" do
      dispatched = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys
                     .group_by { |action| ::Ai::Tools::PlatformApiToolRegistry.all_tools[action] }
                     .transform_values { |actions| actions.map { |a| self.class.dispatched_action_for(a) }.to_set }

      orphans = dispatched.flat_map do |class_name, reachable|
        klass = class_name.safe_constantize
        next [] unless klass&.const_defined?(:ACTION_PERMISSIONS)

        (klass::ACTION_PERMISSIONS.keys - reachable.to_a).map { |key| "#{class_name}: \"#{key}\"" }
      end

      expect(orphans).to be_empty, <<~MSG
        #{orphans.size} ACTION_PERMISSIONS entries are keyed on an action no registry name dispatches to.
        Each one is a permission its author believes is enforced and which is NOT — dispatch falls through
        to the class floor. Either add the McpPlatformToolRegistrar::ACTION_ALIASES row, or delete the entry.

        #{orphans.first(15).join("\n")}
      MSG
    end
  end

  # --- Reading the constants safely ------------------------------------------

  describe ".resolved_permission_for constant reads" do
    # `const_defined?` and `Klass::CONST` are NOT equivalent: const_defined? with
    # inheritance answers true for a same-named TOP-LEVEL constant, because Object
    # is an ancestor of every class, while `::` does not reach it. A resolver that
    # guards with the first and reads with the second would sail past its own
    # guard and pick up (or raise on) an unrelated constant.
    #
    # This costs something to test honestly — the only way to exercise the path is
    # to CREATE the contamination — so it is created for one example and removed
    # in an ensure. Without it the Object skip in #tool_constant is a guard no test
    # holds down, which is the shape that rots into an inert control.
    it "ignores a same-named TOP-LEVEL constant" do
      unladdered = Class.new(Ai::Tools::BaseTool) do
        const_set(:REQUIRED_PERMISSION, "fixture.read")
      end

      expect(unladdered.const_defined?(:ACTION_PERMISSIONS)).to be(false)
      Object.const_set(:ACTION_PERMISSIONS, { "fixture_verb" => "leaked.from.object" }.freeze)
      expect(unladdered.const_defined?(:ACTION_PERMISSIONS)).to be(true),
        "Object contamination is no longer visible through const_defined? — this example proves nothing"

      expect(described_class.resolved_permission_for(unladdered, "fixture_verb")).to eq("fixture.read")
    ensure
      Object.send(:remove_const, :ACTION_PERMISSIONS) if Object.const_defined?(:ACTION_PERMISSIONS, false)
    end
  end

  # --- One resolver, not two -------------------------------------------------

  # The resolution rule is subtle enough that a second copy is a second place to
  # get the alias hop wrong — which is precisely how four verbs survived inside
  # b07585402's own fix. The rake that generates docs/reference/auto/mcp-tools.md
  # must CALL the shared resolver rather than re-derive it.
  describe "shared resolution" do
    let(:rake_source) { File.read(Rails.root.join("lib", "tasks", "mcp_tool_catalog.rake")) }
    let(:rake_code_lines) { rake_source.each_line.reject { |line| line.strip.start_with?("#") } }

    it "exposes the resolver as a public class method" do
      expect(described_class).to respond_to(:resolved_permission_for)
    end

    it "is the only implementation — the catalog rake calls it" do
      # Scoped to CODE lines. An unscoped containment check passes on the
      # comment that merely NAMES the resolver — citing a comment as evidence
      # for code is the exact failure this file's header lectures about, and it
      # would survive deleting the call itself.
      calls = rake_code_lines.grep(/resolved_permission_for/)

      expect(calls).not_to be_empty,
        "lib/tasks/mcp_tool_catalog.rake has no non-comment line calling " \
        "Ai::Tools::McpPlatformToolRegistrar.resolved_permission_for"
    end

    it "leaves no second copy of the ladder lookup in the rake" do
      # Deliberately a CONTAINMENT check on the lookup expression, not on a
      # comment: the rake still discusses ACTION_PERMISSIONS in prose, and must
      # be free to.
      offenders = rake_source.each_line.with_index(1).filter_map do |line, number|
        next if line.strip.start_with?("#")
        next unless line.include?("ACTION_PERMISSIONS")

        "mcp_tool_catalog.rake:#{number}: #{line.strip}"
      end

      expect(offenders).to be_empty,
        "the rake re-derives the ladder instead of calling " \
        "Ai::Tools::McpPlatformToolRegistrar.resolved_permission_for:\n#{offenders.join("\n")}"
    end
  end
end
