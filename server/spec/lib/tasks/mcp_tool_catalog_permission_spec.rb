# frozen_string_literal: true

require "rails_helper"

# IMP-a63365dc0f41 — the published MCP tool catalog must state the permission
# that ACTUALLY gates each action, not its tool class's floor.
#
# server/lib/tasks/mcp_tool_catalog.rake used to compute the published value as
#
#     permission = klass.const_defined?(:REQUIRED_PERMISSION) ? klass::REQUIRED_PERMISSION : nil
#
# which is the CLASS-LEVEL floor. Dispatch resolves the per-action ladder first
# (`ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION`), so every laddered verb
# published a permission strictly lower than its real bar — a privilege
# UNDERSTATEMENT on the surface an operator reads when sizing an MCP grant.
# 337 of the 604 advertised actions were affected; system_rotate_vault_transit_pepper
# (really system.fleet.autonomy) and system_deploy_platform (really
# system.platform.deploy) both published "system.nodes.read".
#
# The catalog is generated, so nobody hand-reviews it, and scripts/
# check-mcp-catalog-fresh.sh only checks that it is FRESH — never that it is
# CORRECT. This spec is the correctness half: it parses the committed artifact
# and holds it to an equality over the whole permission mapping.
#
# Freshness and correctness are complementary: a regression in the generator
# either drifts the committed file (freshness fails) or is regenerated into it
# (this spec fails).
#
# The loop is only as closed as this spec's own resolution rule, though. The
# first cut of BOTH the generator and this spec looked the ladder up by
# REGISTRY key, and CodeMemoryTool keys its ladder on the DISPATCHED action
# ("upsert_node", not "code_upsert_node") — so the spec shared the generator's
# blind spot and would have gone green over four knowledge-graph write verbs
# still published at the "ai.agents.read" floor. The resolution below therefore
# reads McpPlatformToolRegistrar::ACTION_ALIASES, which is the dispatch table
# itself, and the code_* spot checks below pin the four literals independently.
RSpec.describe "docs/reference/auto/mcp-tools.md publishes per-action permissions" do
  # A method, not a constant: a constant assigned inside an RSpec block lands
  # on Object, where a same-named constant in another spec file can clobber it.
  def self.catalog_path
    Rails.root.join("..", "docs", "reference", "auto", "mcp-tools.md")
  end

  # Parse `### \`action\`` headings and the `- **Permission**: value` line that
  # follows each one. Deliberately literal about the emitted markup: if the
  # generator changes its heading or field format, this yields nothing and the
  # size guards below fail loudly rather than vacuously passing.
  def self.published_permissions
    @published_permissions ||= begin
      text = File.read(catalog_path)
      result = {}
      current = nil
      text.each_line do |line|
        if (m = line.match(/\A### `([a-z0-9_]+)`\s*\z/))
          current = m[1]
        elsif current && (m = line.match(/\A- \*\*Permission\*\*: (.+?)\s*\z/))
          result[current] = m[1]
          current = nil
        end
      end
      result
    end
  end

  def published_permissions
    self.class.published_permissions
  end

  # The action the registrar actually DISPATCHES for a registry name. For 25
  # names that is an alias of the key (ACTION_ALIASES, applied at
  # mcp_platform_tool_registrar.rb:152), and a ladder is keyed on the action
  # that RUNS — see the rule stated at code_memory_tool.rb:22-25.
  def self.dispatched_action_for(registry_name)
    ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(registry_name, registry_name)
  end

  # The permission each action REALLY resolves to at dispatch time, computed
  # from the tool classes themselves: the class's ACTION_PERMISSIONS entry for
  # the dispatched action when it has one, else the class floor. Mirrors
  # Ai::Tools::SystemFleetTool#required_perm_for and its 25 siblings.
  def self.expected_permissions
    @expected_permissions ||= ::Ai::Tools::PlatformApiToolRegistry::TOOLS.each_with_object({}) do |(action, class_name), acc|
      klass = class_name.safe_constantize
      next unless klass

      ladder = klass.const_defined?(:ACTION_PERMISSIONS) ? klass::ACTION_PERMISSIONS : {}
      floor  = klass.const_defined?(:REQUIRED_PERMISSION) ? klass::REQUIRED_PERMISSION : nil

      acc[action] = ladder[dispatched_action_for(action)] || floor
    end
  end

  def expected_permissions
    self.class.expected_permissions
  end

  # Actions whose ladder entry DIFFERS from their class floor. These are the
  # only actions that can distinguish a correct generator from the broken one:
  # a class where the two coincide emits the same string either way.
  def self.laddered_above_floor
    @laddered_above_floor ||= ::Ai::Tools::PlatformApiToolRegistry::TOOLS.filter_map do |action, class_name|
      klass = class_name.safe_constantize
      next unless klass&.const_defined?(:ACTION_PERMISSIONS)

      entry = klass::ACTION_PERMISSIONS[dispatched_action_for(action)]
      floor = klass.const_defined?(:REQUIRED_PERMISSION) ? klass::REQUIRED_PERMISSION : nil
      next if entry.nil? || entry == floor

      action
    end
  end

  it "parses every advertised action out of the committed catalog" do
    expect(published_permissions.size).to eq(::Ai::Tools::PlatformApiToolRegistry::TOOLS.size),
      "parsed #{published_permissions.size} `### \\`action\\`` + Permission pairs out of the catalog but the " \
      "registry advertises #{::Ai::Tools::PlatformApiToolRegistry::TOOLS.size} actions — the parser or the " \
      "generator's markup changed; every assertion below is unreliable until this matches"
  end

  it "has a non-trivial number of actions whose real permission is stricter than their class floor" do
    # Guards the oracle itself: if this set were empty (or tiny) every
    # assertion below would pass against a generator that emits only floors.
    expect(self.class.laddered_above_floor.size).to be > 330
  end

  # SPOT ORACLE — real destructive verbs whose ladder entry is strictly
  # stricter than SystemFleetTool's "system.nodes.read" floor. Literal
  # expected strings, so these hold even if the resolution convention above is
  # itself wrong.
  {
    "system_rotate_vault_transit_pepper" => "system.fleet.autonomy",
    "system_deploy_platform"             => "system.platform.deploy",
    "system_gitops_apply_proposal"       => "system.modules.update",
    "system_terminate_instance"          => "system.instances.control",
    "system_destroy_instance"            => "system.instances.control"
  }.each do |action, real_permission|
    it "publishes #{action} as #{real_permission}, not the class floor" do
      floor = ::Ai::Tools::SystemFleetTool::REQUIRED_PERMISSION
      expect(::Ai::Tools::PlatformApiToolRegistry::TOOLS[action]).to eq("Ai::Tools::SystemFleetTool")
      expect(real_permission).not_to eq(floor),
        "#{action}'s ladder entry no longer differs from the floor — pick another destructive verb, " \
        "this one can no longer distinguish a correct generator from the broken one"

      expect(published_permissions[action]).to eq(real_permission)
    end
  end

  # SPOT ORACLE, ALIAS ARM — CodeMemoryTool bundles knowledge-graph WRITE and
  # DESTRUCTIVE verbs behind an "ai.agents.read" floor and ladders each one up.
  # Its ladder is keyed on the dispatched action, so these four are invisible to
  # a registry-key lookup: they are the only actions in the catalog that
  # distinguish a dispatch-faithful generator from a merely ladder-aware one.
  # Literal expected strings, independent of the resolution rule above.
  %w[code_upsert_node code_create_relation code_prune_stale code_bulk_index].each do |action|
    it "publishes #{action} as ai.knowledge_graph.manage despite its ladder being alias-keyed" do
      expect(::Ai::Tools::PlatformApiToolRegistry::TOOLS[action]).to eq("Ai::Tools::CodeMemoryTool")
      expect(::Ai::Tools::CodeMemoryTool::REQUIRED_PERMISSION).to eq("ai.agents.read")
      expect(::Ai::Tools::CodeMemoryTool::ACTION_PERMISSIONS[action]).to be_nil,
        "#{action} is now a literal ladder key — this example no longer proves the alias hop is honored"

      expect(published_permissions[action]).to eq("ai.knowledge_graph.manage")
    end
  end

  # RATCHET — equality over the WHOLE mapping, not a spot check. An existence
  # check cannot see an omission, and an omission (one class's ladder skipped)
  # is exactly the failure shape here.
  it "publishes the ladder entry for EVERY action that has one" do
    mismatches = self.class.laddered_above_floor.filter_map do |action|
      published = published_permissions[action]
      next if published == expected_permissions[action]

      "#{action}: published #{published.inspect}, real gate #{expected_permissions[action].inspect}"
    end

    expect(mismatches).to be_empty, <<~MSG
      #{mismatches.size} of #{self.class.laddered_above_floor.size} laddered actions publish a permission
      that is not the one dispatch enforces. Regenerate:
      cd server && bundle exec rails mcp:generate_tool_catalog

      #{mismatches.first(15).join("\n")}
    MSG
  end

  # The fallback half: an action with no ladder entry must still publish its
  # class floor. Without this, a generator that emitted "none" everywhere for
  # unladdered actions would pass the ratchet above.
  it "publishes the class floor for every action with no ladder entry" do
    unladdered = expected_permissions.keys - self.class.laddered_above_floor
    expect(unladdered.size).to be > 100

    mismatches = unladdered.filter_map do |action|
      expected = expected_permissions[action] || "none"
      next if published_permissions[action] == expected

      "#{action}: published #{published_permissions[action].inspect}, floor #{expected.inspect}"
    end

    expect(mismatches).to be_empty, mismatches.first(15).join("\n")
  end
end
